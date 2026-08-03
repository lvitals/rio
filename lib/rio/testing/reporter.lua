-- rio/lib/rio/testing/reporter.lua

local WarningRegistry = require("rio.testing.warning_registry")

local M = {}

local ANSI_PATTERN = "\27%[[%d;?]*[mKhlABCDEFGJKST]"
local DEFAULT_SUITE = "Other"
local SCHEMA_VERSION = 1

local adapter_labels = {
    mysql = "MySQL",
    postgresql = "PostgreSQL",
    postgres = "PostgreSQL",
    sqlite = "SQLite"
}

local acronyms = {
    api = "API",
    cli = "CLI",
    db = "DB",
    http = "HTTP",
    json = "JSON",
    jwt = "JWT",
    mysql = "MySQL",
    postgres = "PostgreSQL",
    postgresql = "PostgreSQL",
    sql = "SQL",
    sqlite = "SQLite",
    ui = "UI"
}

local section_noise_words = {
    benchmark = true,
    benchmarks = true,
    connectivity = true,
    info = true,
    level = true,
    performance = true
}

local metric_noise_words = {
    factor = true
}

local unit_labels = {
    req = "request",
    stmt = "statement"
}

local unit_suffixes = {
    req = "req/s",
    stmt = "stmt/s"
}

local function strip_ansi(value)
    return tostring(value or ""):gsub(ANSI_PATTERN, "")
end

local function normalize_words(value)
    local words = {}
    value = tostring(value or ""):lower():gsub("[^%w]+", " ")

    for word in value:gmatch("%S+") do
        table.insert(words, acronyms[word] or word:gsub("^%l", string.upper))
    end

    return words
end

local function phrase(words)
    return table.concat(words or {}, " ")
end

local function readable_phrase(words)
    local result = {}

    for index, word in ipairs(words or {}) do
        if index == 1 or word:match("^%u+$") or word == "SQLite" then
            table.insert(result, word)
        else
            table.insert(result, word:lower())
        end
    end

    return table.concat(result, " ")
end

local function remove_repeated_words(primary, secondary)
    local seen = {}
    local result = {}

    for _, word in ipairs(primary or {}) do
        seen[tostring(word):lower()] = true
    end

    for _, word in ipairs(secondary or {}) do
        if not seen[tostring(word):lower()] then
            table.insert(result, word)
        end
    end

    return result
end

local function remove_words(words, ignored)
    local result = {}
    for _, word in ipairs(words or {}) do
        if not ignored[tostring(word):lower()] and not tonumber(word) then
            table.insert(result, word)
        end
    end
    return result
end

local function sentence_case(value)
    value = tostring(value or "")
    return value:sub(1, 1):upper() .. value:sub(2)
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
        local candidate = trimmed

        if trimmed:sub(1, 1) ~= "{" then
            candidate = trimmed:match("({.*})%s*$")
        end

        if candidate and candidate:sub(1, 1) == "{" and candidate:sub(-1) == "}" then
            decoded = decode_json_line(candidate) or decoded
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

    local nested_dir = source:match("^test/([^/]+)/")
    if nested_dir then
        return phrase(normalize_words(nested_dir))
    end

    local file_prefix = source:match("^test/([^_/%-]+)")
    if file_prefix then
        return phrase(normalize_words(file_prefix))
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

local function normalize_adapter(adapter)
    adapter = tostring(adapter or ""):lower()
    if adapter == "postgres" then
        return "postgresql"
    end
    return adapter
end

local function adapter_label(adapter)
    adapter = normalize_adapter(adapter)
    return adapter_labels[adapter] or adapter
end

local function add_database_skip(registry, adapter, detail)
    adapter = normalize_adapter(adapter)
    if adapter == "" then return end

    registry:add({
        key = "database." .. adapter .. ".unavailable",
        category = "database",
        subject = adapter_label(adapter),
        reason = "driver unavailable",
        message = adapter_label(adapter),
        detail = detail
    })
end

local function add_warning_from_line(environment_registry, warning_registry, line)
    local module = line:match("Database driver '([^']+)' is not installed")
    if module then
        local adapter = module:match("%.([^%.]+)$") or module
        add_database_skip(environment_registry, adapter, "missing `" .. module .. "`")
        return
    end

    local skip_context = line:match("%[SKIP%]%s+%[([^%]]+)%]")
    if skip_context then
        local adapter = line:match("Connection failed for ([%w_%-]+)")
        if adapter then
            add_database_skip(environment_registry, adapter, "connection failed")
        else
            warning_registry:add(
                "skip:" .. skip_context,
                skip_context,
                line:gsub("^%s*%[SKIP%]%s*", "")
            )
        end
    end
end

local function collect_notices(output)
    local environments = WarningRegistry.new()
    local warnings = WarningRegistry.new()

    for line in strip_ansi(output):gmatch("[^\r\n]+") do
        add_warning_from_line(environments, warnings, line)
    end

    return environments:all(), warnings:all()
end

local function collect_performance(output)
    local metrics = {}
    local current_section

    local function section_phrase(section)
        return readable_phrase(remove_words(normalize_words(section), section_noise_words))
    end

    local function metric_words(label)
        local metric_name, unit = tostring(label or ""):match("^(.-)%s*%((.-)%)$")
        local words = {}
        local unit_key = unit and unit:match("^([%a]+)") and unit:match("^([%a]+)"):lower()

        for word in tostring(metric_name or label):lower():gmatch("%w+") do
            if not metric_noise_words[word] and not tonumber(word) then
                table.insert(words, word)
            end
        end

        if unit_key and unit_labels[unit_key] then
            table.insert(words, 1, unit_labels[unit_key])
        end

        return words
    end

    local function display_label_for(section, label)
        local section_words = remove_words(normalize_words(section), section_noise_words)
        local metric_words_list = remove_repeated_words(section_words, metric_words(label))
        local section_text = readable_phrase(section_words)
        local metric_text = table.concat(metric_words_list, " ")

        if section_text ~= "" and metric_text ~= "" then
            return sentence_case(section_text .. " " .. metric_text)
        end

        if metric_text ~= "" then
            return sentence_case(metric_text)
        end

        return sentence_case(section_text)
    end

    local function add_metric(label, value)
        label = label:gsub("%s+$", "")
        table.insert(metrics, {
            suite = current_section,
            label = label,
            display_label = display_label_for(current_section, label),
            value = value
        })
    end

    local function append_unit_from_label(label, value)
        local unit = tostring(label or ""):match("%((.-)%)")
        local unit_key = unit and unit:match("^([%a]+)") and unit:match("^([%a]+)"):lower()

        if unit_key and unit_suffixes[unit_key] then
            return tostring(value) .. " " .. unit_suffixes[unit_key]
        end

        return value
    end

    for line in strip_ansi(output):gmatch("[^\r\n]+") do
        local structured_section, structured_label, structured_value =
            line:match("^%[RIO_PERF%]\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if structured_section and structured_label and structured_value then
            current_section = structured_section
            add_metric(structured_label, structured_value)
        end

        local section = line:match("^│%s*([%u][%u%s%d%(%):%-]+)%s*│$")
            or line:match("^%s*([%u][%u%s%d%(%):%-]+)%s*$")
        if section then
            current_section = section:gsub("%s+$", "")
        end

        local label, value = line:match("PASS%s+([%w%s%(%)/:%-]+)%s+│%s+([%d%.]+%s*req/s)")
        if label and value then
            add_metric(label, value)
        end

        label, value = line:match("PASS%s+([%w%s%(%)/:%-]+)%s+│%s+([%d%.]+x faster)")
        if label and value then
            add_metric(label, value)
        end

        label, value = line:match("PASS%s+([%w%s%(%)/:%-]+)%s+│%s+([%d%.]+)%s+│")
        if label and value and tostring(label):find("%(") then
            add_metric(label, append_unit_from_label(label, value))
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
    local environment_skips, warnings = collect_notices(output)
    local summary = {
        schema_version = SCHEMA_VERSION,
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
        environment_skips = environment_skips,
        warnings = warnings,
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
        elseif summary.exit_code ~= 0 then
            local message = strip_ansi(output):match("^%s*(.-)%s*$")
            if message == "" then
                message = "Busted failed before producing parseable output."
            end

            local result = {
                name = "Unable to parse Busted output",
                message = message
            }
            local group = ensure_group(summary.groups, summary.group_order, DEFAULT_SUITE)
            group.tests = 1
            group.errors = 1
            summary.tests = 1
            summary.errors = 1
            table.insert(summary.errors_list, result)
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
