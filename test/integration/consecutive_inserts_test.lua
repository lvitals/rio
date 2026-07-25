if not describe then
    print("\n" .. string.rep("=", 60))
    print("[ERROR] This test file must be run using the 'busted' test runner.")
    print("Usage: busted " .. (arg and arg[0] or "test/integration/consecutive_inserts_test.lua"))
    print(string.rep("=", 60) .. "\n")
    os.exit(1)
end

local test_config = require("test.test_config")

local ADAPTER_CASES = {
    { name = "sqlite", label = "sqlite:file", database = "test_rio_consecutive.sqlite3" },
    { name = "sqlite", label = "sqlite:memory", database = ":memory:" },
    { name = "mysql", label = "mysql" },
    { name = "postgres", label = "postgres" },
}

local POOL_SIZES = { 1, 2, 5 }
local ITERATIONS = 20

local function pk_clause(adapter_name, column)
    if adapter_name == "postgres" then
        return column .. " SERIAL PRIMARY KEY"
    elseif adapter_name == "mysql" then
        return column .. " INT AUTO_INCREMENT PRIMARY KEY"
    end
    return column .. " INTEGER PRIMARY KEY AUTOINCREMENT"
end

local function reset_modules(adapter_name)
    package.loaded["rio.database.manager"] = nil
    package.loaded["rio.database.query_builder"] = nil
    package.loaded["rio.database.model"] = nil
    package.loaded["rio.database.adapters.base"] = nil
    package.loaded["rio.database.adapters." .. adapter_name] = nil
end

local function load_stack(adapter_name)
    reset_modules(adapter_name)
    local DBManager = require("rio.database.manager")
    local Model = require("rio.database.model")
    local QueryBuilder = require("rio.database.query_builder")
    DBManager.verbose = false
    return DBManager, Model, QueryBuilder
end

local function config_for(case, pool_size)
    local cfg = {}
    for k, v in pairs(test_config.configs[case.name]) do cfg[k] = v end
    cfg.pool = pool_size
    if case.database then cfg.database = case.database end
    return cfg
end

local function connection_marker_sql(adapter_name)
    if adapter_name == "postgres" then return "SELECT pg_backend_pid() as marker" end
    if adapter_name == "mysql" then return "SELECT CONNECTION_ID() as marker" end
    return nil
end

for _, case in ipairs(ADAPTER_CASES) do
    for _, pool_size in ipairs(POOL_SIZES) do
        describe(string.format("ORM insert visibility [%s, pool=%d]", case.label, pool_size), function()
            local DBManager, Model, QueryBuilder, Workflow, Version, Manual
            local available = true

            setup(function()
                if test_config.skip_if_no_db(case.name, "Consecutive Inserts") then
                    available = false
                    return
                end

                DBManager, Model, QueryBuilder = load_stack(case.name)
                DBManager.initialize(config_for(case, pool_size))

                DBManager.query("DROP TABLE IF EXISTS rio_ci_versions")
                DBManager.query("DROP TABLE IF EXISTS rio_ci_workflows")
                DBManager.query("DROP TABLE IF EXISTS rio_ci_manual")
                DBManager.query(string.format([[
                    CREATE TABLE rio_ci_workflows (
                        %s,
                        name VARCHAR(255) UNIQUE NOT NULL
                    )
                ]], pk_clause(case.name, "workflow_pk")))
                DBManager.query(string.format([[
                    CREATE TABLE rio_ci_versions (
                        %s,
                        workflow_pk INTEGER NOT NULL,
                        version_num INTEGER NOT NULL
                    )
                ]], pk_clause(case.name, "version_pk")))
                DBManager.query([[
                    CREATE TABLE rio_ci_manual (
                        code VARCHAR(64) PRIMARY KEY,
                        name VARCHAR(255) NOT NULL
                    )
                ]])

                Workflow = Model:extend({
                    table_name = "rio_ci_workflows",
                    primary_key = "workflow_pk",
                    fillable = { "name" },
                    timestamps = false,
                })
                Version = Model:extend({
                    table_name = "rio_ci_versions",
                    primary_key = "version_pk",
                    fillable = { "workflow_pk", "version_num" },
                    timestamps = false,
                })
                Manual = Model:extend({
                    table_name = "rio_ci_manual",
                    primary_key = "code",
                    fillable = { "code", "name" },
                    timestamps = false,
                })
            end)

            teardown(function()
                if not DBManager then return end
                DBManager.query("DROP TABLE IF EXISTS rio_ci_versions")
                DBManager.query("DROP TABLE IF EXISTS rio_ci_workflows")
                DBManager.query("DROP TABLE IF EXISTS rio_ci_manual")
                DBManager.disconnect()
                if case.name == "sqlite" and case.database and case.database ~= ":memory:" then
                    os.remove(case.database)
                end
            end)

            before_each(function()
                if not available then return end
                DBManager.clear_query_cache()
                DBManager.query("DELETE FROM rio_ci_versions")
                DBManager.query("DELETE FROM rio_ci_workflows")
                DBManager.query("DELETE FROM rio_ci_manual")
            end)

            it("keeps consecutive Model:save inserts immediately visible", function()
                if not available then return end

                local stale = Workflow:where("name", "workflow-1"):first()
                assert.is_nil(stale)

                for i = 1, ITERATIONS do
                    local workflow = Workflow:new({ name = "workflow-" .. i })
                    assert.is_true(workflow:save())
                    assert.is_not_nil(workflow.workflow_pk)

                    local found = Workflow:find(workflow.workflow_pk)
                    assert.is_not_nil(found)
                    assert.equals("workflow-" .. i, found.name)

                    local raw = DBManager.query(
                        "SELECT workflow_pk, name FROM rio_ci_workflows WHERE workflow_pk = ?",
                        { workflow.workflow_pk }
                    )
                    assert.equals(1, #raw)
                    assert.equals("workflow-" .. i, raw[1].name)

                    local qb = QueryBuilder.table("rio_ci_workflows")
                        :where("workflow_pk", workflow.workflow_pk)
                        :first()
                    assert.is_not_nil(qb)

                    local version = Version:new({
                        workflow_pk = workflow.workflow_pk,
                        version_num = i,
                    })
                    assert.is_true(version:save())
                    assert.is_not_nil(Version:find(version.version_pk))
                end

                local refreshed = Workflow:where("name", "workflow-1"):first()
                assert.is_not_nil(refreshed)
            end)

            it("supports manual string primary keys", function()
                if not available then return end

                local manual = Manual:new({ code = "manual-key-1", name = "Manual" })
                assert.is_true(manual:save())
                assert.equals("manual-key-1", manual.code)

                local found = Manual:find("manual-key-1")
                assert.is_not_nil(found)
                assert.equals("Manual", found.name)
            end)

            it("pins transaction work to one connection and reuses cleanly after rollback", function()
                if not available then return end

                local marker_sql = connection_marker_sql(case.name)
                local before_marker, after_marker

                local committed_id, err = DBManager.transaction(function()
                    if marker_sql then before_marker = DBManager.query(marker_sql)[1].marker end

                    local workflow = Workflow:new({ name = "tx-workflow" })
                    assert.is_true(workflow:save())

                    local version = Version:new({ workflow_pk = workflow.workflow_pk, version_num = 1 })
                    assert.is_true(version:save())

                    if marker_sql then after_marker = DBManager.query(marker_sql)[1].marker end
                    return workflow.workflow_pk
                end)

                assert.is_nil(err)
                assert.is_not_nil(committed_id)
                if marker_sql then assert.equals(tostring(before_marker), tostring(after_marker)) end
                assert.is_not_nil(Workflow:find(committed_id))

                local rolled_back_id, rollback_err = DBManager.transaction(function()
                    local first = Workflow:new({ name = "dup-name" })
                    assert.is_true(first:save())
                    local second = Workflow:new({ name = "dup-name" })
                    if not second:save() then error("constraint violation") end
                    return first.workflow_pk
                end)

                assert.is_nil(rolled_back_id)
                assert.is_not_nil(rollback_err)
                assert.equals(0, Workflow:where("name", "dup-name"):count())

                local reusable = Workflow:new({ name = "after-rollback" })
                assert.is_true(reusable:save())
                assert.is_not_nil(Workflow:find(reusable.workflow_pk))
            end)
        end)
    end
end
