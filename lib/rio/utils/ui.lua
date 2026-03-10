-- rio/lib/rio/utils/ui.lua
-- Professional UI Utilities for the Rio Framework CLI

local M = {}

-- ANSI Colors
local colors = {
    reset = "\27[0m",
    green = "\27[32m",
    red = "\27[31m",
    cyan = "\27[36m",
    yellow = "\27[33m",
    blue = "\27[34m",
    magenta = "\27[35m",
    white = "\27[37m",
    bold = "\27[1m",
    dim = "\27[2m"
}

M.colors = colors

-- Private Helpers
local function get_visible_len(s)
    if not s then return 0 end
    local stripped = tostring(s):gsub("\27%[[%d;]*m", "")
    local ok, len = pcall(utf8.len, stripped)
    return (ok and len) or #stripped
end

local function utf8_truncate(s, max_len)
    if get_visible_len(s) <= max_len then return s end
    local res = ""
    local count = 0
    for _, c in utf8.codes(tostring(s)) do
        local char = utf8.char(c)
        if count + 1 > max_len - 3 then break end
        res = res .. char
        count = count + 1
    end
    return res .. "..."
end

local function get_terminal_width()
    local default = 80
    local f = io.popen("tput cols 2>/dev/null")
    if f then
        local res = f:read("*a")
        f:close()
        local cols = tonumber(res:match("%d+"))
        if cols then 
            return math.max(40, math.min(80, cols - 2)) 
        end
    end
    return default
end

M.drawing_box = false

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

function M.status(label, success, details)
    local width = get_terminal_width()
    local inner_width = width - 2
    
    if not M.drawing_box then
        print("\n" .. colors.bold .. colors.cyan .. "╭" .. string.rep("─", inner_width) .. "╮" .. colors.reset)
    end

    local icon = success and (colors.green .. "✓ PASS") or (colors.red .. "✗ FAIL")
    local pipe_pos = math.floor(inner_width * 0.55)
    local max_label_len = pipe_pos - 10
    
    local display_label = utf8_truncate(label, max_label_len)
    local left_part = "  " .. icon .. " " .. colors.white .. display_label
    local vis_left = get_visible_len(left_part)
    
    local fill = pipe_pos - vis_left
    if fill < 1 then fill = 1 end
    
    local line = left_part .. colors.reset .. string.rep(" ", fill)
    
    if details then
        local max_details_len = inner_width - pipe_pos - 3
        local display_details = utf8_truncate(tostring(details), max_details_len)
        line = line .. colors.dim .. "│ " .. colors.reset .. colors.cyan .. display_details
    end
    
    local vis_line = get_visible_len(line)
    local final_padding = inner_width - vis_line
    if final_padding < 0 then final_padding = 0 end
    
    print(colors.bold .. colors.cyan .. "│" .. colors.reset .. line .. string.rep(" ", final_padding) .. colors.bold .. colors.cyan .. "│" .. colors.reset)

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

    local left_part = "  " .. colors.white .. label
    local vis_left = get_visible_len(left_part)
    
    -- Proportional pipe position
    local pipe_pos = math.floor(inner_width * 0.45)
    local fill = pipe_pos - vis_left
    if fill < 1 then fill = 1 end
    
    local line = left_part .. colors.reset .. string.rep(" ", fill)
    
    if value then
        local max_val_len = inner_width - pipe_pos - 3
        local display_val = utf8_truncate(tostring(value), max_val_len)
        line = line .. colors.dim .. "│ " .. colors.reset .. colors.cyan .. display_val
    end
    
    local vis_line = get_visible_len(line)
    local final_padding = inner_width - vis_line
    if final_padding < 0 then final_padding = 0 end
    
    print(colors.bold .. colors.cyan .. "│" .. colors.reset .. line .. string.rep(" ", final_padding) .. colors.bold .. colors.cyan .. "│" .. colors.reset)

    if not M.drawing_box then
        print(colors.bold .. colors.cyan .. "╰" .. string.rep("─", inner_width) .. "╯" .. colors.reset)
    end
end

function M.info(msg)
    if M.drawing_box then
        local width = get_terminal_width()
        local inner_width = width - 2
        local content = "  " .. colors.yellow .. "ℹ " .. colors.reset .. colors.white .. utf8_truncate(msg, inner_width - 4) .. colors.reset
        local vis_len = get_visible_len(content)
        local padding = inner_width - vis_len
        if padding < 0 then padding = 0 end
        print(colors.bold .. colors.cyan .. "│" .. colors.reset .. content .. string.rep(" ", padding) .. colors.bold .. colors.cyan .. "│" .. colors.reset)
    else
        print("  " .. colors.yellow .. "ℹ " .. colors.reset .. colors.white .. msg .. colors.reset)
    end
end

function M.text(msg, color)
    local c = color or colors.white
    if M.drawing_box then
        local width = get_terminal_width()
        local inner_width = width - 2
        local content = "  " .. c .. utf8_truncate(msg, inner_width - 4) .. colors.reset
        local vis_len = get_visible_len(content)
        local padding = inner_width - vis_len
        if padding < 0 then padding = 0 end
        print(colors.bold .. colors.cyan .. "│" .. colors.reset .. content .. string.rep(" ", padding) .. colors.bold .. colors.cyan .. "│" .. colors.reset)
    else
        print("  " .. c .. msg .. colors.reset)
    end
end

function M.line(msg, color)
    local c = color or colors.white
    print("  " .. c .. msg .. colors.reset)
end

function M.row_simple(label, value)
    local pipe_pos = 30
    local left = "  " .. colors.white .. label
    local vis_left = get_visible_len(left)
    local fill = pipe_pos - vis_left
    if fill < 1 then fill = 1 end

    print(left .. string.rep(" ", fill) .. colors.dim .. "» " .. colors.reset .. colors.cyan .. tostring(value) .. colors.reset)
end

function M.header(title)
    print("\n" .. colors.bold .. colors.magenta .. " ❯ " .. colors.white .. title:upper() .. colors.reset)
end

return M
