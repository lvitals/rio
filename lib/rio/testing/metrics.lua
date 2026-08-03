-- rio/lib/rio/testing/metrics.lua

local M = {}

function M.record(section, label, value)
    if os.getenv("RIO_TEST_REPORT_METRICS") ~= "1" then
        return
    end

    print(table.concat({
        "[RIO_PERF]",
        tostring(section or ""),
        tostring(label or ""),
        tostring(value or "")
    }, "\t"))
end

return M
