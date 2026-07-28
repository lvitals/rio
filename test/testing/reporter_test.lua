if not describe then
    print("Usage: busted test/testing/reporter_test.lua")
    os.exit(1)
end

package.path = "./?.lua;./?/init.lua;lib/?.lua;lib/?/init.lua;" .. package.path

local reporter = require("rio.testing.reporter")

local function find_by_subject(items, subject)
    for _, item in ipairs(items or {}) do
        if item.subject == subject then
            return item
        end
    end
end

describe("Rio testing reporter", function()
    it("groups test results by source path", function()
        local summary = reporter.build([[{"duration":1.25,"successes":[{"name":"database ok","trace":{"short_src":"test/database/model_test.lua"},"element":{"duration":0.12}},{"name":"cli ok","trace":{"short_src":"test/cli/shell_test.lua"},"element":{"duration":0.04}}],"failures":[],"errors":[],"pendings":[]}]], 0)

        assert.equals("passed", summary.status)
        assert.equals(2, summary.tests)
        assert.equals(1, summary.groups.Database.tests)
        assert.equals(1, summary.groups.CLI.tests)
    end)

    it("deduplicates unavailable database environments by root cause", function()
        local output = table.concat({
            "Database driver 'luasql.mysql' is not installed",
            "[SKIP] [Async Suite: mysql] Connection failed for mysql. Check configuration.",
            "Database driver 'luasql.postgres' is not installed",
            "[SKIP] [Transaction Suite: postgres] Connection failed for postgres. Check configuration.",
            [[{"duration":0,"successes":[],"failures":[],"errors":[],"pendings":[]}]]
        }, "\n")

        local summary = reporter.build(output, 0)
        local mysql = find_by_subject(summary.environment_skips, "MySQL")
        local postgres = find_by_subject(summary.environment_skips, "PostgreSQL")

        assert.equals(2, #summary.environment_skips)
        assert.equals(0, #summary.warnings)
        assert.equals(2, mysql.count)
        assert.equals("missing `luasql.mysql`", mysql.detail)
        assert.equals(2, postgres.count)
        assert.equals("missing `luasql.postgres`", postgres.detail)
    end)

    it("keeps repeated performance metric names with their section context", function()
        local output = table.concat({
            "│                      QUERY CACHE PERFORMANCE (LEVEL 1)                       │",
            "│  ✓ PASS Speedup Factor                   │ 6.8x faster                       │",
            "│                          HIGH CONCURRENCY BENCHMARK                          │",
            "│  ✓ PASS Throughput                       │ 2205.57 req/s                     │",
            [[{"duration":0,"successes":[],"failures":[],"errors":[],"pendings":[]}]]
        }, "\n")

        local summary = reporter.build(output, 0)

        assert.equals(2, #summary.performance)
        assert.equals("QUERY CACHE PERFORMANCE (LEVEL 1)", summary.performance[1].suite)
        assert.equals("Speedup Factor", summary.performance[1].label)
        assert.equals("Query cache speedup", summary.performance[1].display_label)
        assert.equals("HIGH CONCURRENCY BENCHMARK", summary.performance[2].suite)
        assert.equals("Throughput", summary.performance[2].label)
        assert.equals("HTTP concurrency throughput", summary.performance[2].display_label)
    end)

    it("reports unparseable failing output as an error", function()
        local summary = reporter.build("module 'missing' not found", 1)

        assert.equals("failed", summary.status)
        assert.equals(1, summary.errors)
        assert.equals("Unable to parse Busted output", summary.errors_list[1].name)
    end)
end)
