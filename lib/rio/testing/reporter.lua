-- rio/lib/rio/testing/reporter.lua

local WarningRegistry = require("rio.testing.warning_registry")

local M = {}

local ANSI_PATTERN = "\27%[[%d;?]*[mKhlABCDEFGJKST]"
local DEFAULT_SUITE = "Tests"

local suite_labels = {
    ["test/cli/"] = "CLI",
    ["test/core/"] = "Core",
    ["test/database/"] = "Database",
    ["test/integration/"] = "Integration",
    ["test/middleware/"] = "Middleware",
    ["test/utils/"] = "Utilities",
    ["test/fixtures/"] = "Fixtures"
}

local function strip_ansi(value)
    return tostring(value or ""):gsub(ANSI_PATTERN, "")
end

local function decode_json_line(line)
    local ok_cjson, cjson = pcall(require, "cjson")
    if not ok_cjson then
        ok_cjson, cjson = pcall(require, "cjson.safe")
    end
    if not ok_cjson then
        return nil
    end

    local ok, decoded = pcall(cjson.decode, line)
    if ok and type(decoded) == "table" then
        return decoded
    end
    return nil
end

local function extract_json(output)
    local decoded
    for line in tostring(output or ""):gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed:sub(1, 1) == "{" and trimmed:sub(-1) == "}" then
            decoded = decode_json_line(trimmed) or decoded
        end
    end
    return decoded
end

local function source_for(result)
    local trace = result.trace or (result.element and result.element.trace) or {}
    local source = trace.short_src or trace.source or ""
    return tostring(source):gsub("^@", "")
end

local function duration_for(result)
    local element = result.element or {}
    return tonumber(element.duration or result.duration) or 0
end

local function suite_for(source)
    source = tostring(source or "")
    if source:match("^test/async_") then
        return "Async"
    end
    if source:match("^test/benchmark") then
        return "Performance"
    end
    for prefix, label in pairs(suite_labels) do
        if source:find(prefix, 1, true) == 1 then
            return label
        end
    end
    return DEFAULT_SUITE
end

local function ensure_group(groups, order, name)
    local group = groups[name]
    if group then return group end

    group = {
        name = name,
        tests = 0,
        passed = 0,
        failed = 0,
        errors = 0,
        pending = 0,
        duration = 0
    }
    groups[name] = group
    table.insert(order, name)
    return group
end

local function add_results(summary, list, status)
    for _, result in ipairs(list or {}) do
        local source = source_for(result)
        local group = ensure_group(summary.groups, summary.group_order, suite_for(source))
        local duration = duration_for(result)

        group.tests = group.tests + 1
        group.duration = group.duration + duration
        summary.tests = summary.tests + 1

        if status == "passed" then
            group.passed = group.passed + 1
            summary.passed = summary.passed + 1
        elseif status == "failed" then
            group.failed = group.failed + 1
            summary.failed = summary.failed + 1
            table.insert(summary.failures, result)
        elseif status == "error" then
            group.errors = group.errors + 1
            summary.errors = summary.errors + 1
            table.insert(summary.errors_list, result)
        elseif status == "pending" then
            group.pending = group.pending + 1
            summary.pending = summary.pending + 1
        end
    end
end

local function add_warning_from_line(registry, line)
    local module = line:match("Database driver '([^']+)' is not installed")
    if module then
        local adapter = module:match("%.([^%.]+)$") or module
        registry:add(
            "missing-driver:" .. adapter,
            adapter .. " driver unavailable",
            "missing `" .. module .. "`"
        )
        return
    end

    local skip_context = line:match("%[SKIP%]%s+%[([^%]]+)%]")
    if skip_context then
        local adapter = line:match("Connection failed for ([%w_%-]+)") or skip_context
        registry:add(
            "skip:" .. adapter,
            skip_context,
            line:gsub("^%s*%[SKIP%]%s*", "")
        )
    end
end

local function collect_warnings(output)
    local registry = WarningRegistry.new()
    for line in strip_ansi(output):gmatch("[^\r\n]+") do
        add_warning_from_line(registry, line)
    end
    return registry:all()
end

local function collect_performance(output)
    local metrics = {}
    for line in strip_ansi(output):gmatch("[^\r\n]+") do
        local label, value = line:match("PASS%s+([%w%s%(%)/:%-]+)%s+│%s+([%d%.]+%s*req/s)")
        if label and value then
            table.insert(metrics, { label = label:gsub("%s+$", ""), value = value })
        end

        label, value = line:match("PASS%s+([%w%s%(%)/:%-]+)%s+│%s+([%d%.]+x faster)")
        if label and value then
            table.insert(metrics, { label = label:gsub("%s+$", ""), value = value })
        end
    end
    return metrics
end

local function message_for(result)
    return tostring(result.message
        or (result.element and result.element.message)
        or (result.trace and result.trace.message)
        or result.name
        or "failure")
end

local function clean_message(message, location)
    message = tostring(message or "")
    location = tostring(location or "")

    if location ~= "" and message:find(location .. ":", 1, true) == 1 then
        return message:sub(#location + 2):match("^%s*(.-)%s*$")
    end

    return message
end

local function location_for(result)
    local trace = result.trace or (result.element and result.element.trace) or {}
    local source = tostring(trace.short_src or trace.source or ""):gsub("^@", "")
    local line = trace.currentline or trace.linedefined
    if source ~= "" and line then
        local numeric_line = tonumber(line)
        return source .. ":" .. tostring(numeric_line and math.floor(numeric_line) or line)
    end
    return source
end

function M.build(output, exit_code)
    local data = extract_json(output)
    local summary = {
        status = "failed",
        exit_code = exit_code or 1,
        tests = 0,
        passed = 0,
        failed = 0,
        errors = 0,
        pending = 0,
        duration = 0,
        groups = {},
        group_order = {},
        warnings = collect_warnings(output),
        performance = collect_performance(output),
        failures = {},
        errors_list = {},
        raw_output = output or ""
    }

    if data then
        summary.duration = tonumber(data.duration) or 0
        add_results(summary, data.successes, "passed")
        add_results(summary, data.failures, "failed")
        add_results(summary, data.errors, "error")
        add_results(summary, data.pendings, "pending")
    else
        local successes, failures, errors, pending, duration = strip_ansi(output):match(
            "(%d+)%s+successes%s+/%s+(%d+)%s+failures%s+/%s+(%d+)%s+errors%s+/%s+(%d+)%s+pending%s+:%s+([%d%.]+)%s+seconds"
        )
        if successes then
            summary.passed = tonumber(successes) or 0
            summary.failed = tonumber(failures) or 0
            summary.errors = tonumber(errors) or 0
            summary.pending = tonumber(pending) or 0
            summary.duration = tonumber(duration) or 0
            summary.tests = summary.passed + summary.failed + summary.errors + summary.pending
            local group = ensure_group(summary.groups, summary.group_order, DEFAULT_SUITE)
            group.tests = summary.tests
            group.passed = summary.passed
            group.failed = summary.failed
            group.errors = summary.errors
            group.pending = summary.pending
            group.duration = summary.duration
        end
    end

    summary.status = (summary.failed == 0 and summary.errors == 0 and summary.exit_code == 0) and "passed" or "failed"

    for _, result in ipairs(summary.failures) do
        result._location = location_for(result)
        result._message = clean_message(message_for(result), result._location)
    end
    for _, result in ipairs(summary.errors_list) do
        result._location = location_for(result)
        result._message = clean_message(message_for(result), result._location)
    end

    return summary
end

return M
