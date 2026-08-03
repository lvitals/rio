local cqueues = require("cqueues")
local test_config = require("test.test_config")

-- The sequential tests in transaction_test.lua prove DB.transaction() pins a
-- single connection for the whole callback, but a purely sequential test
-- can't actually reproduce the original bug report: with only one connection
-- ever checked out, a LIFO pool always hands the same connection back even
-- with the old (unpinned) implementation. The real bug required genuine
-- concurrency - multiple coroutines sharing a pool, with a cooperative yield
-- (e.g. waiting on the network) happening *between* BEGIN and the rest of a
-- transaction's statements, so an unrelated coroutine could grab the
-- now-pooled, still-BEGIN'd connection out from under it.
--
-- Postgres is the adapter with real cooperative polling (send_query/getfd),
-- so pg_sleep() inside a transaction forces exactly that yield. With a pool
-- smaller than the number of concurrent transactions, the old
-- begin()/commit() (each an independent pool checkout) would let workers'
-- inserts and commits drift across connections, corrupting or losing rows.
describe("DB.transaction() under concurrent coroutines sharing a small pool [postgres]", function()
    local adapter_name = "postgres"
    local DBManager
    local WORKERS = 8
    local POOL_SIZE = 3

    setup(function()
        if test_config.skip_if_no_db(adapter_name, "Transaction Pool Concurrency") then return end

        package.loaded["rio.database.manager"] = nil
        package.loaded["rio.database.adapters.postgres"] = nil
        DBManager = require("rio.database.manager")
        DBManager.verbose = false

        local base_config = test_config.configs[adapter_name]
        local config = {}
        for k, v in pairs(base_config) do config[k] = v end
        config.pool = POOL_SIZE

        DBManager.initialize(config)
        DBManager.query("DROP TABLE IF EXISTS rio_tx_concurrency")
        DBManager.query("CREATE TABLE rio_tx_concurrency (id SERIAL PRIMARY KEY, worker INTEGER, value INTEGER)")
    end)

    teardown(function()
        if test_config.skip_if_no_db(adapter_name, "Transaction Pool Concurrency") then return end
        DBManager.query("DROP TABLE IF EXISTS rio_tx_concurrency")
    end)

    it(string.format("commits exactly one uncorrupted row per worker (%d workers, pool=%d)", WORKERS, POOL_SIZE), function()
        if test_config.skip_if_no_db(adapter_name, "Transaction Pool Concurrency") then return end

        local cq = cqueues.new()
        local errors = {}

        for worker = 1, WORKERS do
            cq:wrap(function()
                local _, err = DBManager.transaction(function()
                    -- Forces a real cooperative yield mid-transaction, giving
                    -- other coroutines a chance to run while this
                    -- connection would have been sitting unpinned in the
                    -- pool under the old implementation.
                    DBManager.query("SELECT pg_sleep(0.2)")

                    local id = DBManager.insert(
                        "INSERT INTO rio_tx_concurrency (worker, value) VALUES (?, ?)",
                        {worker, worker}
                    )
                    if not id then error("insert did not return an id for worker " .. worker) end

                    -- Read our own write back inside the same still-open
                    -- transaction; this must see it regardless of any other
                    -- worker's concurrent, uncommitted transaction.
                    local mine = DBManager.query(
                        "SELECT worker, value FROM rio_tx_concurrency WHERE id = ?",
                        {id}
                    )
                    if not mine or #mine ~= 1 or tonumber(mine[1].worker) ~= worker then
                        error(string.format(
                            "worker %d read back mismatched row: %s",
                            worker, mine and mine[1] and tostring(mine[1].worker) or "nil"
                        ))
                    end
                end)
                if err then
                    table.insert(errors, string.format("worker %d: %s", worker, tostring(err.message or err)))
                end
            end)
        end

        assert.is_true(cq:loop())

        assert.equals(0, #errors, table.concat(errors, " | "))

        local rows = DBManager.query("SELECT worker, value FROM rio_tx_concurrency ORDER BY worker")
        assert.equals(WORKERS, #rows, "expected exactly one committed row per worker")

        for _, row in ipairs(rows) do
            assert.equals(tonumber(row.worker), tonumber(row.value), "a row was corrupted across workers")
        end
    end)
end)
