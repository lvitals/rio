-- rio/lib/rio/testing/formatters/terminal.lua

local ui = require("rio.utils.ui")
local colors = ui.colors

local M = {}

local BOX_BORDER_WIDTH = 2
local BOX_HORIZONTAL_PADDING = " "
local SUITE_COLUMN = 34
local COUNT_COLUMN = 10
local DURATION_COLUMN = 10
local PERFORMANCE_LABEL_COLUMN = 36
local WARNING_MESSAGE_COLUMN = 34

local function terminal_width()
    return ui.terminal_width()
end

local function inner_width()
    return terminal_width() - BOX_BORDER_WIDTH
end

local function colorize(color, value)
    return (color or "") .. tostring(value or "") .. colors.reset
end

local function pad_right(value, width)
    value = tostring(value or "")
    if #value >= width then
        return value:sub(1, width)
    end
    return value .. string.rep(" ", width - #value)
end

local function pad_left(value, width)
    value = tostring(value or "")
    if #value >= width then
        return value:sub(1, width)
    end
    return string.rep(" ", width - #value) .. value
end

local function print_indented(value, indentation)
    indentation = indentation or ""
    for line in (tostring(value or "") .. "\n"):gmatch("(.-)\r?\n") do
        print(indentation .. line)
    end
end

local function line()
    print(colors.gray .. string.rep("─", terminal_width()) .. colors.reset)
end

local function box_line(value)
    local text = tostring(value or "")
    local width = inner_width()

    if ui.visible_len(text) > width then
        text = text:sub(1, width)
    end

    local padding = width - ui.visible_len(text)
    if padding < 0 then padding = 0 end

    print(colors.cyan .. "│" .. colors.reset .. text .. string.rep(" ", padding) .. colors.cyan .. "│" .. colors.reset)
end

local function box_label_value(label, value)
    local text = BOX_HORIZONTAL_PADDING .. tostring(label or "")
    local suffix = tostring(value or "") .. BOX_HORIZONTAL_PADDING
    local available = inner_width() - ui.visible_len(text) - ui.visible_len(suffix)

    if available < 1 then
        return box_line(text)
    end

    box_line(text .. string.rep(" ", available) .. suffix)
end

function M.header(options)
    options = options or {}
    local version = options.version or "unknown"
    local lua_version = options.lua_version or _VERSION
    local env = options.environment or "test"

    local width = inner_width()

    print(colors.cyan .. "╭" .. string.rep("─", width) .. "╮" .. colors.reset)
    box_label_value("Rio Test Runner", "v" .. version)
    box_line(" " .. lua_version .. " · Environment " .. env .. " · Format compact")
    print(colors.cyan .. "╰" .. string.rep("─", width) .. "╯" .. colors.reset)
    print("")
end

local function group_status(group)
    if group.errors > 0 then return "ERROR", colors.red end
    if group.failed > 0 then return "FAIL", colors.red end
    if group.tests == group.pending and group.tests > 0 then return "SKIP", colors.yellow end
    return "PASS", colors.green
end

function M.groups(summary, options)
    if options and options.quiet then return end

    for _, name in ipairs(summary.group_order or {}) do
        local group = summary.groups[name]
        local status, color = group_status(group)
        local duration = string.format("%.3fs", group.duration or 0)
        local count = tostring(group.tests or 0) .. " tests"

        print("  "
            .. colorize(color, pad_right(status, 5))
            .. " "
            .. pad_right(group.name, SUITE_COLUMN)
            .. pad_left(count, COUNT_COLUMN)
            .. " "
            .. colorize(colors.gray, pad_left(duration, DURATION_COLUMN)))
    end
end

function M.performance(summary)
    if not summary.performance or #summary.performance == 0 then return end

    print("")
    line()
    print("")
    print("  " .. colorize(colors.blue, "Performance"))
    print("")
    for _, metric in ipairs(summary.performance) do
        print("  " .. pad_right(metric.label, PERFORMANCE_LABEL_COLUMN) .. colorize(colors.cyan, metric.value))
    end
end

function M.warnings(summary)
    if not summary.warnings or #summary.warnings == 0 then return end

    print("")
    line()
    print("")
    print("  " .. colorize(colors.yellow, "Warnings"))
    print("")
    for _, warning in ipairs(summary.warnings) do
        local occurrences = warning.count > 1 and (" (" .. warning.count .. " occurrences)") or ""
        print("  " .. pad_right(warning.message, WARNING_MESSAGE_COLUMN) .. colorize(colors.gray, tostring(warning.detail or "") .. occurrences))
    end
end

local function print_problem(kind, item)
    print("  " .. colorize(colors.red, kind) .. "  " .. tostring(item.name or item._message or "unknown"))
    if item._message and item._message ~= item.name then
        print_indented(item._message, "        ")
    end
    if item._location and item._location ~= "" then
        print("        " .. colorize(colors.gray, item._location))
    end
end

function M.failures(summary)
    if summary.failed == 0 and summary.errors == 0 then return end

    print("")
    line()
    print("")
    print("  " .. colorize(colors.red, "Failed tests"))
    print("")
    for _, item in ipairs(summary.failures or {}) do
        print_problem("FAIL", item)
    end
    for _, item in ipairs(summary.errors_list or {}) do
        print_problem("ERROR", item)
    end
end

function M.summary(summary)
    print("")
    line()
    print("")

    local status_color = summary.status == "passed" and colors.green or colors.red
    local status_text = summary.status == "passed" and "PASS" or "FAIL"
    local parts = {
        tostring(summary.passed) .. " passed",
        tostring(summary.failed) .. " failed",
        tostring(summary.errors) .. " errors",
        tostring(summary.pending) .. " skipped",
        tostring(#(summary.warnings or {})) .. " warnings",
        string.format("%.3fs", summary.duration or 0)
    }

    print("  " .. table.concat(parts, " · "))
    print("")
    print("  " .. colorize(status_color, status_text) .. "  "
        .. (summary.status == "passed" and "All tests completed successfully." or "Test run failed.")
        .. " " .. colorize(colors.gray, "Exit code " .. tostring(summary.exit_code or 0)))
end

function M.render(summary, options)
    local quiet = options and options.quiet

    if not quiet then
        M.groups(summary, options)
        M.performance(summary)
        M.warnings(summary)
    end

    M.failures(summary)
    M.summary(summary)
end

return M
