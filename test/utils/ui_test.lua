if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the \"busted\" test runner.")
    print("Usage: busted test/utils/ui_test.lua")
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local ui = require("rio.utils.ui")

local function strip_ansi(s)
    return tostring(s):gsub("\27%[[%d;?]*[mKhlABCDEFGJKST]", "")
end

local function capture_prints(fn)
    local original_print = _G.print
    local lines = {}

    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            table.insert(parts, tostring(select(i, ...)))
        end
        table.insert(lines, table.concat(parts, "\t"))
    end

    local ok, err = pcall(fn)
    _G.print = original_print

    if not ok then error(err, 2) end
    return strip_ansi(table.concat(lines, "\n"))
end

describe("Rio UI Utils", function()
    it("wraps long status details instead of truncating them", function()
        local detail = table.concat({
            "module/path/component.lua:17",
            "a detailed message that exceeds the inline column",
            "final-status-marker"
        }, " ")
        local output = capture_prints(function()
            ui.status("Long status", false, detail)
        end)

        assert.truthy(output:find("Long status", 1, true))
        assert.truthy(output:find("module/path/component.lua:17", 1, true))
        assert.truthy(output:find("final-status-marker", 1, true))
        assert.is_nil(output:find("%.%.%."))
    end)

    it("wraps long row values instead of truncating them", function()
        local value = table.concat({
            "/root/project/samples/application/controllers",
            "a value that exceeds the inline column",
            "final-row-marker"
        }, "/")
        local output = capture_prints(function()
            ui.row("Long value", value)
        end)

        assert.truthy(output:find("Long value", 1, true))
        assert.truthy(output:find("final-row-marker", 1, true))
        assert.is_nil(output:find("%.%.%."))
    end)
end)
