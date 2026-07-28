if not describe then
    print("Usage: busted test/testing/terminal_formatter_test.lua")
    os.exit(1)
end

package.path = "./?.lua;./?/init.lua;lib/?.lua;lib/?/init.lua;" .. package.path

local terminal_formatter = require("rio.testing.formatters.terminal")

local function strip_ansi(value)
    return tostring(value):gsub("\27%[[%d;?]*[mKhlABCDEFGJKST]", "")
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

    local ok, err = xpcall(fn, debug.traceback)
    _G.print = original_print

    if not ok then error(err, 0) end
    return strip_ansi(table.concat(lines, "\n"))
end

describe("Rio terminal test formatter", function()
    it("renders performance labels without joining truncated words to values", function()
        local first_label = "Cache speedup"
        local first_value = "3.8x faster"
        local second_label = "Concurrency throughput"
        local second_value = "2652.24 req/s"
        local long_label = "Postgres multi statement statement throughput"
        local long_value = "4884.40 stmt/s"

        local output = capture_prints(function()
            terminal_formatter.render({
                status = "passed",
                passed = 2,
                failed = 0,
                errors = 0,
                pending = 0,
                duration = 0.1,
                exit_code = 0,
                groups = {},
                group_order = {},
                performance = {
                    {
                        display_label = first_label,
                        value = first_value
                    },
                    {
                        display_label = second_label,
                        value = second_value
                    },
                    {
                        display_label = long_label,
                        value = long_value
                    }
                },
                warnings = {},
                environment_skips = {},
                failures = {},
                errors_list = {}
            })
        end)

        assert.truthy(output:find(first_label, 1, true))
        assert.truthy(output:find(first_value, 1, true))
        assert.truthy(output:find(second_label, 1, true))
        assert.truthy(output:find(second_value, 1, true))
        assert.truthy(output:find(long_label, 1, true))
        assert.truthy(output:find(long_value, 1, true))
        assert.is_nil(output:find("Sp3%.8x"))
        assert.is_nil(output:find("Throughpu2652"))
        assert.is_nil(output:find("statement t  4884", 1, true))
    end)

    it("renders skipped database environments separately from warnings", function()
        local output = capture_prints(function()
            terminal_formatter.render({
                status = "passed",
                passed = 12,
                failed = 0,
                errors = 0,
                pending = 0,
                duration = 0.42,
                exit_code = 0,
                groups = {},
                group_order = {},
                performance = {},
                warnings = {},
                environment_skips = {
                    {
                        subject = "MySQL",
                        reason = "driver unavailable",
                        detail = "missing `luasql.mysql`",
                        count = 7
                    }
                },
                failures = {},
                errors_list = {}
            })
        end)

        assert.truthy(output:find("Skipped environments", 1, true))
        assert.truthy(output:find("MySQL", 1, true))
        assert.truthy(output:find("1 environments skipped", 1, true))
        assert.truthy(output:find("7 occurrences", 1, true))
        assert.is_nil(output:find("1 warnings", 1, true))
    end)
end)
