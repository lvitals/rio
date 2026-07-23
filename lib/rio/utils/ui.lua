-- rio/lib/rio/utils/ui.lua
-- Professional UI Utilities for the Rio Framework CLI

local M = {}

-- Professional UI Utilities for the Rio Framework CLI
local compat = require("rio.utils.compat")
local colors = compat.colors
local utf8 = compat.utf8

M.colors = colors

-- Bootstrap-inspired alert styles
local alerts = {
    primary   = { icon = "●", color = colors.blue },
    secondary = { icon = "●", color = colors.gray },
    success   = { icon = "✓", color = colors.green },
    danger    = { icon = "✗", color = colors.red },
    warning   = { icon = "⚠", color = colors.yellow },
    info      = { icon = "ℹ", color = colors.cyan },
    light     = { icon = "•", color = colors.white },
    dark      = { icon = "■", color = colors.magenta }
}

-- Private Helpers
local function get_visible_len(s)
    if not s then return 0 end
    -- Remove ALL ANSI escape codes (colors, bold, etc.)
    -- Using a more comprehensive pattern
    local stripped = tostring(s):gsub("\27%[[%d;?]*[mKhlABCDEFGJKST]", "")
    
    if utf8 then
        local ok, len = pcall(utf8.len, stripped)
        if ok and len then return len end
    end
    
    -- Fallback: Count UTF-8 characters manually if library is missing
    local _, count = stripped:gsub("[%z\1-\127\194-\244][\128-\191]*", "")
    return count
end

local function utf8_truncate(s, max_len)
    local vis_len = get_visible_len(s)
    if vis_len <= max_len then return s end
    
    if not utf8 then
        return tostring(s):sub(1, max_len - 3) .. "..."
    end

    local res = ""
    local count = 0
    for _, c in utf8.codes(tostring(s)) do
        local char = utf8.char(c)
        local char_vis = get_visible_len(char)
        if count + char_vis > max_len - 3 then break end
        res = res .. char
        count = count + char_vis
    end
    return res .. "..."
end

local function get_terminal_width()
    local default = 80
    local f = io.popen("tput cols 2>/dev/null")
    local cols
    if f then
        local res = f:read("*a")
        f:close()
        cols = tonumber(res:match("%d+"))
    end
    
    cols = cols or default
    -- Use 80 as maximum, but stay within terminal bounds
    return math.max(40, math.min(80, cols))
end

local function process_text_lines(text)
    local lines = {}
    for line in string.gmatch(tostring(text) .. "\n", "(.-)\n") do
        table.insert(lines, line)
    end
    if lines[#lines] == "" and #lines > 1 then table.remove(lines) end
    
    local processed = {}
    for _, line in ipairs(lines) do
        -- process \t
        line = line:gsub("\t", "    ")
        -- process \b
        while line:find("[^\b]\b") do
            line = line:gsub("[^\b]\b", "")
        end
        line = line:gsub("^\b+", "")
        -- process \r
        if line:find("\r") then
            line = line:match(".*\r(.*)")
        end
        table.insert(processed, line)
    end
    return processed
end

local function utf8_take(s, max_len)
    s = tostring(s or "")
    if max_len <= 0 then return "", s end
    if get_visible_len(s) <= max_len then return s, "" end

    if not utf8 then
        return s:sub(1, max_len), s:sub(max_len + 1)
    end

    local res = ""
    local count = 0
    local bytes = 0
    for pos, c in utf8.codes(s) do
        local char = utf8.char(c)
        local char_vis = get_visible_len(char)
        if count + char_vis > max_len then break end
        res = res .. char
        count = count + char_vis
        bytes = pos + #char - 1
    end

    return res, s:sub(bytes + 1)
end

local function trim_left(s)
    return tostring(s or ""):gsub("^%s+", "")
end

local function wrap_visible_line(line, width)
    local wrapped = {}
    line = tostring(line or "")

    if width <= 0 then
        table.insert(wrapped, line)
        return wrapped
    end

    if line == "" then
        table.insert(wrapped, "")
        return wrapped
    end

    while get_visible_len(line) > width do
        local chunk, rest = utf8_take(line, width)
        local break_at = chunk:match("^.*()%s+%S*$")

        if break_at and break_at > 1 then
            rest = line:sub(break_at)
            chunk = chunk:sub(1, break_at - 1)
        end

        table.insert(wrapped, chunk)
        line = trim_left(rest)
        if line == "" then break end
    end

    if line ~= "" then table.insert(wrapped, line) end
    return wrapped
end

local function wrap_text(text, width)
    local wrapped = {}
    for _, line in ipairs(process_text_lines(text)) do
        for _, wrapped_line in ipairs(wrap_visible_line(line, width)) do
            table.insert(wrapped, wrapped_line)
        end
    end
    if #wrapped == 0 then table.insert(wrapped, "") end
    return wrapped
end

local function print_box_line(content, inner_width)
    local vis_line = get_visible_len(content)
    local padding = inner_width - vis_line
    if padding < 0 then padding = 0 end
    print(colors.bold .. colors.cyan .. "│" .. colors.reset .. content .. string.rep(" ", padding) .. colors.bold .. colors.cyan .. "│" .. colors.reset)
end

local function render_pair(left_content, pipe_pos, value, value_color, inner_width)
    local fill = pipe_pos - get_visible_len(left_content)
    if fill < 1 then fill = 1 end

    local line = left_content .. colors.reset .. string.rep(" ", fill)
    if value == nil then
        print_box_line(line, inner_width)
        return
    end

    local value_text = tostring(value)
    local separator = colors.dim .. "│ " .. colors.reset
    local inline_width = inner_width - pipe_pos - get_visible_len(separator)
    local value_lines = process_text_lines(value_text)
    if #value_lines == 1 and get_visible_len(value_lines[1]) <= inline_width then
        print_box_line(line .. separator .. value_color .. value_lines[1], inner_width)
        return
    end

    print_box_line(line, inner_width)
    local continuation_prefix = "  "
    for _, wrapped_line in ipairs(wrap_text(value_text, inner_width - get_visible_len(continuation_prefix))) do
        print_box_line(continuation_prefix .. value_color .. wrapped_line .. colors.reset, inner_width)
    end
end

M.drawing_box = false

-- Core Components

function M.box(title, content_fn)
    local width = get_terminal_width()
    local inner_width = width - 2
    local h_line = string.rep("─", inner_width)
    
    print("\n" .. colors.bold .. colors.cyan .. "╭" .. h_line .. "╮" .. colors.reset)
    
    local title_text = " " .. title:upper() .. " "
    local vis_title = get_visible_len(title_text)
    if vis_title > inner_width then
        title_text = utf8_truncate(title_text, inner_width)
        vis_title = get_visible_len(title_text)
    end
    
    local pad_total = inner_width - vis_title
    local left_pad = math.floor(pad_total / 2)
    local right_pad = pad_total - left_pad
    
    print(colors.bold .. colors.cyan .. "│" .. string.rep(" ", left_pad) .. colors.yellow .. title_text .. colors.reset .. colors.bold .. colors.cyan .. string.rep(" ", right_pad) .. "│" .. colors.reset)
    print(colors.bold .. colors.cyan .. "├" .. h_line .. "┤" .. colors.reset)
    
    M.drawing_box = true
    content_fn(width)
    M.drawing_box = false
    
    print(colors.bold .. colors.cyan .. "╰" .. h_line .. "╯" .. colors.reset)
end

function M.alert(kind, msg)
    local style = alerts[kind] or alerts.info
    local icon = style.icon
    local color = style.color
    
    local lines = process_text_lines(msg)
    local width = get_terminal_width()
    local inner_width = width - 2
    
    for i, line in ipairs(lines) do
        local current_icon = (i == 1) and icon or " "
        local icon_vis_len = get_visible_len(current_icon)
        
        -- Construction: "  " (2) + icon + " " (1) + truncated_line
        local prefix = "  " .. current_icon .. " "
        local prefix_len = 2 + icon_vis_len + 1
        local max_line_len = inner_width - prefix_len
        
        local display_line = utf8_truncate(line, max_line_len)
        local line_vis_len = get_visible_len(display_line)
        
        if M.drawing_box then
            local total_vis = prefix_len + line_vis_len
            local padding = inner_width - total_vis
            if padding < 0 then padding = 0 end
            
            -- Print with colors but use calculated padding
            io.write(colors.bold .. colors.cyan .. "│" .. colors.reset)
            io.write("  " .. color .. current_icon .. " " .. colors.reset .. colors.white .. display_line .. colors.reset)
            io.write(string.rep(" ", padding))
            io.write(colors.bold .. colors.cyan .. "│" .. colors.reset .. "\n")
        else
            print("  " .. color .. current_icon .. " " .. colors.reset .. colors.white .. line .. colors.reset)
        end
    end
end

function M.alert_title(kind, title, msg)
    local style = alerts[kind] or alerts.info
    local prefix = style.color .. style.icon .. " " .. title:upper() .. colors.reset
    M.text(prefix .. " " .. colors.gray .. "—" .. colors.reset .. " " .. msg)
end

-- Convenience methods
function M.success(msg) M.alert("success", msg) end
function M.error(msg)   M.alert("danger", msg) end
function M.warn(msg)    M.alert("warning", msg) end

function M.status(label, success, details)
    local width = get_terminal_width()
    local inner_width = width - 2
    
    if not M.drawing_box then
        print("\n" .. colors.bold .. colors.cyan .. "╭" .. string.rep("─", inner_width) .. "╮" .. colors.reset)
    end

    local icon = success and (colors.green .. "✓ PASS") or (colors.red .. "✗ FAIL")
    -- Increase pipe_pos to 55% for more label space
    local pipe_pos = math.floor(inner_width * 0.55)
    local max_label_len = pipe_pos - 10
    
    local display_label = utf8_truncate(label, max_label_len)
    local left_part = "  " .. icon .. " " .. colors.white .. display_label
    render_pair(left_part, pipe_pos, details, colors.cyan, inner_width)

    if not M.drawing_box then
        print(colors.bold .. colors.cyan .. "╰" .. string.rep("─", inner_width) .. "╯" .. colors.reset)
    end
end

function M.row(label, value)
    local width = get_terminal_width()
    local inner_width = width - 2
    
    if not M.drawing_box then
        print("\n" .. colors.bold .. colors.cyan .. "╭" .. string.rep("─", inner_width) .. "╮" .. colors.reset)
    end

    -- Proportional pipe position unified with M.status at 55%
    local pipe_pos = math.floor(inner_width * 0.55)
    local max_label_len = pipe_pos - 4
    
    local display_label = utf8_truncate(label, max_label_len)
    local left_part = "  " .. colors.white .. display_label
    render_pair(left_part, pipe_pos, value, colors.cyan, inner_width)

    if not M.drawing_box then
        print(colors.bold .. colors.cyan .. "╰" .. string.rep("─", inner_width) .. "╯" .. colors.reset)
    end
end

function M.info(msg, label)
    if label then
        -- Backward compatibility for info with labels
        local lines = process_text_lines(msg)
        for i, line in ipairs(lines) do
            local pipe_pos = 30
            local current_label = (i == 1) and label or ""
            local left = "  " .. current_label
            local vis_left = get_visible_len(left)
            local fill = pipe_pos - vis_left
            if fill < 1 then fill = 1 end
            print(left .. string.rep(" ", fill) .. colors.gray .. "» " .. colors.reset .. colors.bold .. colors.white .. line .. colors.reset)
        end
    else
        M.alert("info", msg)
    end
end

function M.text(msg, color)
    local c = color or (colors.bold .. colors.white)
    local lines = process_text_lines(msg)
    for _, line in ipairs(lines) do
        if M.drawing_box then
            local width = get_terminal_width()
            local inner_width = width - 2
            local content = "  " .. c .. utf8_truncate(line, inner_width - 4) .. colors.reset
            local vis_len = get_visible_len(content)
            local padding = inner_width - vis_len
            if padding < 0 then padding = 0 end
            print(colors.bold .. colors.cyan .. "│" .. colors.reset .. content .. string.rep(" ", padding) .. colors.bold .. colors.cyan .. "│" .. colors.reset)
        else
            print("  " .. c .. line .. colors.reset)
        end
    end
end

function M.line(msg, color)
    local c = color or colors.white
    local lines = process_text_lines(msg)
    for _, line in ipairs(lines) do
        print("  " .. c .. line .. colors.reset)
    end
end

function M.row_simple(label, value)
    local pipe_pos = 30
    local left = "  " .. colors.white .. label
    local vis_left = get_visible_len(left)
    local fill = pipe_pos - vis_left
    if fill < 1 then fill = 1 end

    print(left .. string.rep(" ", fill) .. colors.gray .. "» " .. colors.reset .. colors.cyan .. tostring(value) .. colors.reset)
end

function M.header(title)
    print("\n" .. colors.bold .. colors.magenta .. " ❯ " .. colors.white .. title:upper() .. colors.reset)
end

-- Professional SQL-style Table Renderer
function M.table(data, title)
    if title then 
        M.header(title)
    end

    if not data or (type(data) == "table" and #data == 0) then
        M.text(colors.gray .. "  (Empty result set)" .. colors.reset)
        return
    end

    -- Handle Multi-result sets
    if data[1] and type(data[1]) == "table" and data[1][1] and type(data[1][1]) == "table" then
        for i, set in ipairs(data) do
            M.table(set, "Result Set #" .. i)
        end
        return
    end

    -- 1. Extract columns and calculate widths
    local cols = {}
    local first_row = data[1] or {}
    if first_row._attributes then first_row = first_row._attributes end -- Model support
    
    for k, _ in pairs(first_row) do table.insert(cols, k) end
    table.sort(cols)

    local widths = {}
    for _, col in ipairs(cols) do
        widths[col] = get_visible_len(col)
        for _, row in ipairs(data) do
            local r_data = row._attributes or row
            local val = r_data[col]
            local str_val = tostring(val == nil and "NULL" or val)
            widths[col] = math.max(widths[col], get_visible_len(str_val))
        end
    end

    -- 2. Build table strings
    local header = "  |"
    local separator = "  +"
    for _, col in ipairs(cols) do
        header = header .. " " .. col .. string.rep(" ", widths[col] - get_visible_len(col)) .. " |"
        separator = separator .. string.rep("-", widths[col] + 2) .. "+"
    end

    -- 3. Print with box awareness
    M.text(colors.white .. separator .. colors.reset)
    M.text(colors.bold .. colors.white .. header .. colors.reset)
    M.text(colors.white .. separator .. colors.reset)

    for _, row in ipairs(data) do
        local r_data = row._attributes or row
        local line = "  |"
        for _, col in ipairs(cols) do
            local val = r_data[col]
            local str_val = tostring(val == nil and "NULL" or val)
            line = line .. " " .. str_val .. string.rep(" ", widths[col] - get_visible_len(str_val)) .. " |"
        end
        M.text(line)
    end
    M.text(colors.white .. separator .. colors.reset)
end

return M
