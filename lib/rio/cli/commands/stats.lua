-- rio/lib/rio/cli/commands/stats.lua

local Command = require("rio.cli.command")

local M = {}

local CATEGORIES = {
    { name = "Controllers",      path = "app/controllers",      pattern = "%.lua$" },
    { name = "Middlewares",      path = "app/middleware",       pattern = "%.lua$" },
    { name = "Models",           path = "app/models",           pattern = "%.lua$" },
    { name = "Mailers",          path = "app/mailers",          pattern = "%.lua$" },
    { name = "Views",            path = "app/views",            pattern = "%.etl$" },
    { name = "Libraries",        path = "lib",                  pattern = "%.lua$" },
    { name = "Initializers",     path = "config/initializers",  pattern = "%.lua$" },
    { name = "Controller tests", path = "test/controllers",     pattern = "%.lua$" },
    { name = "Model tests",      path = "test/models",          pattern = "%.lua$" },
    { name = "Mailer tests",     path = "test/mailers",         pattern = "%.lua$" },
    { name = "Integration tests",path = "test/integration",     pattern = "%.lua$" },
}

local function analyze_file(file_path)
    local lines = 0
    local loc = 0
    local methods = 0
    local f = io.open(file_path, "r")
    if not f then return 0, 0, 0 end

    for line in f:lines() do
        lines = lines + 1
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not trimmed:match("^%-%-") then
            loc = loc + 1
        end

        if line:match("function%s+[%w_%.%:]+") or line:match("[%w_%.%:]+%s*=%s*function") then
            methods = methods + 1
        end
    end
    f:close()
    return lines, loc, methods
end

local function scan_dir(cat_name, dir_path, pattern)
    local total_lines, total_loc, total_methods, total_files = 0, 0, 0, 0

    if cat_name == "Middlewares" then
        local f_mw_path = "config/middlewares.lua"
        local f_mw = io.open(f_mw_path, "r")
        if f_mw then
            local content = f_mw:read("*a")
            f_mw:close()

            local l, lc = analyze_file(f_mw_path)
            total_lines = total_lines + l
            total_loc = total_loc + lc

            for _ in content:gmatch("\"([%w_]+)\"") do
                total_files = total_files + 1
            end
            for _ in content:gmatch("'([%w_]+)'") do
                total_files = total_files + 1
            end
        end
    end

    for _, file in ipairs(require("rio.cli.files").find(dir_path, { pattern = pattern })) do
        local l, lc, m = analyze_file(file)
        total_lines = total_lines + l
        total_loc = total_loc + lc
        total_methods = total_methods + m
        if cat_name ~= "Middlewares" then
            total_files = total_files + 1
        end
    end

    return total_lines, total_loc, total_methods, total_files
end

function M.run(ctx)
    ctx.ui.header("Project Statistics")

    local grand_total = { lines = 0, loc = 0, files = 0, methods = 0 }
    local code_loc = 0
    local test_loc = 0

    ctx.ui.box("Category Summary", function()
        local header_row = string.format("  %-20s │ %5s │ %5s │ %7s │ %7s", "Name", "Lines", "LOC", "Modules", "Funcs")
        ctx.ui.text(header_row, ctx.colors.yellow)
        ctx.ui.text(string.rep("─", #header_row), ctx.colors.dim)

        for _, cat in ipairs(CATEGORIES) do
            local l, lc, m, f = scan_dir(cat.name, cat.path, cat.pattern)
            if f > 0 or not cat.name:find("test") then
                local line = string.format("  %-20s │ %5d │ %5d │ %7d │ %7d", cat.name, l, lc, f, m)
                ctx.ui.text(line)

                grand_total.lines = grand_total.lines + l
                grand_total.loc = grand_total.loc + lc
                grand_total.files = grand_total.files + f
                grand_total.methods = grand_total.methods + m

                if cat.name:lower():find("test") then
                    test_loc = test_loc + lc
                else
                    code_loc = code_loc + lc
                end
            end
        end

        ctx.ui.text(string.rep("─", #header_row), ctx.colors.dim)
        local total_row = string.format("  %-20s │ %5d │ %5d │ %7d │ %7d",
            "TOTAL", grand_total.lines, grand_total.loc, grand_total.files, grand_total.methods)
        ctx.ui.text(total_row, ctx.colors.bold .. ctx.colors.white)
    end)

    ctx.ui.box("Ratios & Metrics", function()
        local ratio = code_loc > 0 and string.format("1:%.1f", test_loc / code_loc) or "N/A"
        ctx.ui.row("Code LOC", code_loc)
        ctx.ui.row("Test LOC", test_loc)
        ctx.ui.row("Code to Test Ratio", ratio)

        local complexity = grand_total.methods > 0 and math.floor(grand_total.loc / grand_total.methods) or 0
        ctx.ui.row("Avg LOC per function", complexity)
    end)
end

function M.command()
    return Command.new({
        name = "stats",
        help = function(ctx)
            ctx.show_stats_help()
        end,
        run = function(ctx)
            M.run(ctx)
            return true
        end
    })
end

return M
