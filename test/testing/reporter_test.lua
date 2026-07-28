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
        assert.equals(1, summary.schema_version)
        assert.equals(2, summary.tests)
        assert.equals(1, summary.groups.Database.tests)
        assert.equals(1, summary.groups.CLI.tests)
    end)

    it("extracts busted json even when a test prints before it on the same line", function()
        local prefix = "[FALLBACK: NO ASYNC DRIVER]"
        local json = [[{"duration":0.5,"successes":[{"name":"ok","trace":{"short_src":"test/database/postgres_adapter_test.lua"},"element":{"duration":0.1}}],"failures":[],"errors":[],"pendings":[]}]]
        local summary = reporter.build(prefix .. " " .. json, 0)

        assert.equals("passed", summary.status)
        assert.equals(1, summary.tests)
        assert.equals(1, summary.groups.Database.tests)
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
        local storage_section = "SQLITE CONNECTIVITY INFO"
        local cache_section = "QUERY CACHE PERFORMANCE (LEVEL 1)"
        local concurrency_section = "HIGH CONCURRENCY BENCHMARK"
        local request_metric = "Throughput (Req/s)"
        local statement_metric = "Throughput (Stmt/s)"
        local speedup_metric = "Speedup Factor"
        local throughput_metric = "Throughput"

        local output = table.concat({
            "│                           " .. storage_section .. "                           │",
            "│  ✓ PASS " .. request_metric .. "              │ 148703.14                         │",
            "│  ✓ PASS " .. statement_metric .. "             │ 73411.91                          │",
            "│                      " .. cache_section .. "                       │",
            "│  ✓ PASS " .. speedup_metric .. "                   │ 6.8x faster                       │",
            "│                          " .. concurrency_section .. "                          │",
            "│  ✓ PASS " .. throughput_metric .. "                       │ 2205.57 req/s                     │",
            [[{"duration":0,"successes":[],"failures":[],"errors":[],"pendings":[]}]]
        }, "\n")

        local summary = reporter.build(output, 0)

        assert.equals(4, #summary.performance)
        assert.equals(storage_section, summary.performance[1].suite)
        assert.equals(request_metric, summary.performance[1].label)
        assert.equals("SQLite request throughput", summary.performance[1].display_label)
        assert.equals("148703.14 req/s", summary.performance[1].value)
        assert.equals(statement_metric, summary.performance[2].label)
        assert.equals("SQLite statement throughput", summary.performance[2].display_label)
        assert.equals("73411.91 stmt/s", summary.performance[2].value)
        assert.equals(cache_section, summary.performance[3].suite)
        assert.equals(speedup_metric, summary.performance[3].label)
        assert.equals("Query cache speedup", summary.performance[3].display_label)
        assert.equals(concurrency_section, summary.performance[4].suite)
        assert.equals(throughput_metric, summary.performance[4].label)
        assert.equals("High concurrency throughput", summary.performance[4].display_label)
    end)

    it("uses a specific group for reporter infrastructure tests", function()
        local summary = reporter.build([[{"duration":0,"successes":[{"name":"reporter ok","trace":{"short_src":"test/testing/reporter_test.lua"},"element":{"duration":0.01}}],"failures":[],"errors":[],"pendings":[]}]], 0)

        assert.equals(1, summary.groups.Testing.tests)
    end)

    it("reports unparseable failing output as an error", function()
        local summary = reporter.build("module 'missing' not found", 1)

        assert.equals("failed", summary.status)
        assert.equals(1, summary.errors)
        assert.equals("Unable to parse Busted output", summary.errors_list[1].name)
    end)
end)
