-- rio/lib/rio/database/query_builder.lua
-- SQL Query Builder inspired by Laravel/Eloquent.

-- USAGE EXAMPLES:
--
-- 1. Basic Query:
--    local QB = require("rio.database.query_builder")
--    local users = QB.table("users"):where("age", ">", 18):get()
--
-- 2. Raw Query with Bindings (SECURE):
--    local results = QB.raw("SELECT * FROM users WHERE name = ? AND age > ?", {"Sara", 18})
--
-- 3. Via Model:
--    local User = require("app.models.user")
--    local users = User:where("status", "active"):orderBy("name"):get()

local QueryBuilder = {}
QueryBuilder.__index = QueryBuilder

-- The DBManager will be responsible for handling the actual connection and execution.
local DBManager = require("rio.database.manager")

-- Creates a new QueryBuilder instance
function QueryBuilder.new(model)
    local self = setmetatable({}, {
        __index = QueryBuilder,
        __tostring = function(q)
            return string.format("Query(%s) { select: [%s] }", q._table or "unknown", table.concat(q._selects, ", "))
        end
    })
    self._model = model
    self._table = model and (model.table_name or model._table) or nil
    self._wheres = {}
    self._selects = {"*"}
    self._joins = {}
    self._orderBy = {}
    self._limit = nil
    self._offset = nil
    self._cache_ttl = nil
    return self
end

-- Defines the cache time for this specific query (in seconds)
function QueryBuilder:cache(ttl)
    self._cache_ttl = ttl or 3600
    return self
end

-- Define table
function QueryBuilder:table(table_name)
    self._table = self:_validateIdentifier(table_name)
    return self
end

-- SELECT
function QueryBuilder:select(...)
    self._selects = {...}
    return self
end

-- WHERE
function QueryBuilder:where(column, operator, value)
    if value == nil then
        value = operator
        operator = "="
    end
    table.insert(self._wheres, { column = column, operator = operator, value = value, type = "AND" })
    return self
end

function QueryBuilder:orWhere(column, operator, value)
    if value == nil then
        value = operator
        operator = "="
    end
    table.insert(self._wheres, { column = column, operator = operator, value = value, type = "OR" })
    return self
end

function QueryBuilder:whereIn(column, values)
    table.insert(self._wheres, { column = column, operator = "IN", value = values, type = "AND" })
    return self
end

function QueryBuilder:whereNull(column)
    table.insert(self._wheres, { column = column, operator = "IS NULL", value = nil, type = "AND" })
    return self
end

function QueryBuilder:whereNotNull(column)
    table.insert(self._wheres, { column = column, operator = "IS NOT NULL", value = nil, type = "AND" })
    return self
end

-- JOIN
function QueryBuilder:join(table_name, first, operator, second)
    if not second then second = operator; operator = "=" end
    table.insert(self._joins, { type = "INNER", table = table_name, first = first, operator = operator, second = second })
    return self
end

function QueryBuilder:leftJoin(table_name, first, operator, second)
    if not second then second = operator; operator = "=" end
    table.insert(self._joins, { type = "LEFT", table = table_name, first = first, operator = operator, second = second })
    return self
end

-- ORDER BY
function QueryBuilder:orderBy(column, direction)
    direction = direction or "ASC"
    table.insert(self._orderBy, { column = column, direction = direction })
    return self
end

-- LIMIT / OFFSET
function QueryBuilder:limit(num) self._limit = num; return self end
function QueryBuilder:offset(num) self._offset = num; return self end
function QueryBuilder:skip(num) return self:offset(num) end
function QueryBuilder:take(num) return self:limit(num) end

-- Pagination
function QueryBuilder:paginate(page, per_page)
    page = page or 1
    per_page = per_page or 15
    self:limit(per_page)
    self:offset((page - 1) * per_page)
    return self
end

-- Internal helper to build WHERE clause
function QueryBuilder:_buildWhere()
    if #self._wheres == 0 then return "" end
    
    local where_clauses = {}
    for i, where in ipairs(self._wheres) do
        local clause
        if where.operator == "IN" then
            local values = {}
            for _, v in ipairs(where.value) do table.insert(values, self:_escapeValue(v)) end
            clause = string.format("%s IN (%s)", where.column, table.concat(values, ", "))
        elseif where.operator == "IS NULL" or where.operator == "IS NOT NULL" then
            clause = string.format("%s %s", where.column, where.operator)
        else
            clause = string.format("%s %s %s", where.column, where.operator, self:_escapeValue(where.value))
        end
        table.insert(where_clauses, (i == 1 and "WHERE " or where.type .. " ") .. clause)
    end
    return " " .. table.concat(where_clauses, " ")
end

-- Builds the SQL query string
function QueryBuilder:toSql()
    local sql = "SELECT " .. table.concat(self._selects, ", ") .. " FROM " .. self._table
    
    for _, join in ipairs(self._joins) do
        sql = sql .. string.format(" %s JOIN %s ON %s %s %s", join.type, join.table, join.first, join.operator, join.second)
    end
    
    sql = sql .. self:_buildWhere()
    
    if #self._orderBy > 0 then
        local orders = {}
        for _, order in ipairs(self._orderBy) do table.insert(orders, order.column .. " " .. order.direction) end
        sql = sql .. " ORDER BY " .. table.concat(orders, ", ")
    end
    
    if self._limit then sql = sql .. " LIMIT " .. self._limit end
    if self._offset then sql = sql .. " OFFSET " .. self._offset end
    
    return sql
end

-- Escapes values for SQL queries.
function QueryBuilder:_escapeValue(value)
    local adapter = DBManager.get_adapter()
    if adapter and adapter.escape_value then
        return adapter.escape_value(value)
    end
    
    -- Fallback
    if type(value) == "string" then
        return "'" .. value:gsub("'", "''"):gsub("\\", "\\\\"):gsub("\0", "") .. "'"
    elseif type(value) == "number" then
        return tostring(value)
    elseif type(value) == "boolean" then
        return value and "TRUE" or "FALSE"
    elseif value == nil then
        return "NULL"
    else
        return "'" .. tostring(value):gsub("'", "''"):gsub("\\", "\\\\"):gsub("\0", "") .. "'"
    end
end

-- Validates table/column names.
function QueryBuilder:_validateIdentifier(identifier)
    if not identifier:match("^[a-zA-Z0-9_.]+$") then
        error("Invalid identifier: " .. identifier)
    end
    return identifier
end

-- Executes a SELECT query and returns all results.
function QueryBuilder:get()
    local sql = self:toSql()
    
    -- 1. Application Cache (Level 2 - Persistent/Manual via :cache())
    if self._cache_ttl and _G.app and _G.app.cache then
        local cache_key = "query:" .. sql:gsub("[^%w]", "_")
        return _G.app.cache:fetch(cache_key, self._cache_ttl, function()
            local results, err = DBManager.query(sql)
            if err then error(err) end
            if self._model and results then return self._model:_hydrateAll(results) end
            return results
        end)
    end

    -- 2. Query Cache (Level 1 - Automatic/Request-level)
    if DBManager.query_cache_enabled and DBManager.query_cache[sql] then
        -- print("DEBUG: Query Cache HIT for: " .. sql)
        return DBManager.query_cache[sql]
    end

    local results, err = DBManager.query(sql)
    if err then error(err) end

    local final_results = results
    if self._model and results then
        final_results = self._model:_hydrateAll(results)
    end
    
    -- Save to Query Cache if enabled
    if DBManager.query_cache_enabled then
        DBManager.query_cache[sql] = final_results
    end

    return final_results
end

-- Alias for get
function QueryBuilder:all()
    return self:get()
end

-- Executes a SELECT query and returns the first result.
function QueryBuilder:first()
    self:limit(1)
    local results = self:get() -- This will throw if there's an error
    
    if results and #results > 0 then
        return results[1]
    end
    
    return nil
end

-- Executes a COUNT query.
function QueryBuilder:count()
    local original_selects = self._selects
    self._selects = {"COUNT(*) as count"}
    
    local sql = self:toSql()
    self._selects = original_selects -- restore
    
    local results, err = DBManager.query(sql)
    if err then error(err) end
    return (results and results[1]) and tonumber(results[1].count) or 0
end

-- Calculation methods
function QueryBuilder:sum(column)
    self._selects = {string.format("SUM(%s) as val", column)}
    local res = self:first()
    return res and tonumber(res.val) or 0
end

function QueryBuilder:avg(column)
    self._selects = {string.format("AVG(%s) as val", column)}
    local res = self:first()
    return res and tonumber(res.val) or 0
end

function QueryBuilder:min(column)
    self._selects = {string.format("MIN(%s) as val", column)}
    local res = self:first()
    return res and res.val or nil
end

function QueryBuilder:max(column)
    self._selects = {string.format("MAX(%s) as val", column)}
    local res = self:first()
    return res and res.val or nil
end

-- Executes an INSERT query.
function QueryBuilder:insert(data)
    if not data or not next(data) then
        return nil, "No data provided for insert"
    end
    
    local columns, values = {}, {}
    for k, v in pairs(data) do
        table.insert(columns, k)
        table.insert(values, self:_escapeValue(v))
    end
    
    local sql = string.format("INSERT INTO %s (%s) VALUES (%s)", self._table, table.concat(columns, ", "), table.concat(values, ", "))
    local res, err = DBManager.insert(sql)
    if err then error(err) end
    return res
end

-- Executes an UPDATE query.
function QueryBuilder:update(data)
    if not data or not next(data) then
        return true -- Nothing to update, consider success
    end
    
    local sets = {}
    for k, v in pairs(data) do
        table.insert(sets, string.format("%s = %s", k, self:_escapeValue(v)))
    end
    local sql = string.format("UPDATE %s SET %s", self._table, table.concat(sets, ", "))
    sql = sql .. self:_buildWhere()
    
    -- print("DEBUG: Generated UPDATE SQL:", sql)
    
    local res, err = DBManager.update(sql)
    if err then error(err) end
    
    -- res should be { affected = n }
    if type(res) == "table" and res.affected then
        return res.affected >= 0
    end
    return res ~= nil
end

-- Executes a DELETE query.
function QueryBuilder:delete()
    local sql = "DELETE FROM " .. self._table
    sql = sql .. self:_buildWhere()
    
    local res, err = DBManager.delete(sql)
    if err then error(err) end

    if type(res) == "table" and res.affected then
        return res.affected >= 0
    end
    return res ~= nil
end

-- Static convenience methods
local M = {}

function M.table(table_name)
    return QueryBuilder.new():table(table_name)
end

-- Executes a raw SQL query.
function M.raw(sql, bindings)
    return DBManager.query(sql, bindings)
end

function M.query(sql, bindings)
    return M.raw(sql, bindings)
end

-- Export the class as well
M.new = QueryBuilder.new

return M
