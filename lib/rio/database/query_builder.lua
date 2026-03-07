-- rio/lib/rio/database/query_builder.lua
-- SQL Query Builder inspired by Laravel/Eloquent.

local QueryBuilder = {}
QueryBuilder.__index = QueryBuilder

local DBManager = require("rio.database.manager")
local string_utils = require("rio.utils.string")

function QueryBuilder.new(model)
    local self = setmetatable({}, {
        __index = function(t, k)
            -- 1. Check QueryBuilder methods
            if QueryBuilder[k] then return QueryBuilder[k] end
            
            -- 2. Scopes Logic: If calling a method not in QB, check if it's a scope in the Model
            if model and model[k] and type(model[k]) == "function" then
                return function(q, ...)
                    return model[k](model, q, ...) or q
                end
            end
            return nil
        end,
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
    self._distinct = false
    return self
end

function QueryBuilder:distinct()
    self._distinct = true
    return self
end

function QueryBuilder:cache(ttl)
    self._cache_ttl = ttl or 3600
    return self
end

function QueryBuilder:table(table_name)
    self._table = self:_validateIdentifier(table_name)
    return self
end

function QueryBuilder:select(...)
    local args = {...}
    if #args > 0 then self._selects = args end
    return self
end

-- WHERE (Supports Closures for grouping)
function QueryBuilder:where(column, operator, value)
    if type(column) == "function" then
        local nested_qb = QueryBuilder.new(self._model)
        column(nested_qb)
        table.insert(self._wheres, { type = "AND", nested = nested_qb._wheres })
        return self
    end

    if value == nil and operator ~= nil then
        value = operator
        operator = "="
    end
    table.insert(self._wheres, { column = column, operator = operator, value = value, type = "AND" })
    return self
end

function QueryBuilder:orWhere(column, operator, value)
    if type(column) == "function" then
        local nested_qb = QueryBuilder.new(self._model)
        column(nested_qb)
        table.insert(self._wheres, { type = "OR", nested = nested_qb._wheres })
        return self
    end

    if value == nil and operator ~= nil then
        value = operator
        operator = "="
    end
    table.insert(self._wheres, { column = column, operator = operator, value = value, type = "OR" })
    return self
end

-- New: Filter by relationship presence (WHERE EXISTS)
function QueryBuilder:whereHas(relation_name, callback)
    return self:_addWhereHas(relation_name, callback, "AND")
end

function QueryBuilder:orWhereHas(relation_name, callback)
    return self:_addWhereHas(relation_name, callback, "OR")
end

function QueryBuilder:_addWhereHas(relation_name, callback, boolean_type)
    if not self._model or not self._model._relations or not self._model._relations[relation_name] then
        error("Relation '" .. tostring(relation_name) .. "' not defined on model " .. (self._model and self._model.table_name or "unknown"))
    end

    local rel_data = self._model._relations[relation_name]
    local rel_meta = rel_data.metadata
    local RelatedModel = require(rel_meta.model_path)
    
    local sub_qb = RelatedModel:query():select("1")
    if callback then callback(sub_qb) end
    
    local foreign_key = rel_meta.foreign_key
    local primary_key = rel_meta.primary_key or "id"
    
    if rel_meta.type == "belongs_to" then
        local fk = foreign_key or (relation_name .. "_id")
        sub_qb:whereColumn(RelatedModel.table_name .. "." .. primary_key, "=", self._table .. "." .. fk)
    else
        local fk = foreign_key or (string_utils.singularize(self._model.table_name) .. "_id")
        sub_qb:whereColumn(RelatedModel.table_name .. "." .. fk, "=", self._table .. "." .. primary_key)
    end
    
    table.insert(self._wheres, { type = boolean_type, raw = "EXISTS (" .. sub_qb:toSql() .. ")" })
    return self
end

function QueryBuilder:whereColumn(first, operator, second)
    table.insert(self._wheres, { type = "AND", raw = string.format("%s %s %s", first, operator, second) })
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
    page = tonumber(page) or 1; per_page = tonumber(per_page) or 15
    self:limit(per_page); self:offset((page - 1) * per_page)
    return self
end

-- Internal helper to build WHERE clause
function QueryBuilder:_buildWhere(wheres_list)
    local target = wheres_list or self._wheres
    if #target == 0 then return "" end
    
    local where_clauses = {}
    for i, w in ipairs(target) do
        local clause
        local boolean_type = (i == 1 and "" or w.type .. " ")
        
        if w.nested then
            clause = "(" .. self:_buildWhere(w.nested) .. ")"
        elseif w.raw then
            clause = w.raw
        elseif w.operator == "IN" then
            local values = {}
            for _, v in ipairs(w.value) do table.insert(values, self:_escapeValue(v)) end
            clause = string.format("%s IN (%s)", w.column, table.concat(values, ", "))
        elseif w.operator == "IS NULL" or w.operator == "IS NOT NULL" then
            clause = string.format("%s %s", w.column, w.operator)
        else
            clause = string.format("%s %s %s", w.column, w.operator, self:_escapeValue(w.value))
        end
        table.insert(where_clauses, boolean_type .. clause)
    end
    
    local final = table.concat(where_clauses, " ")
    return wheres_list and final or " WHERE " .. final
end

-- Builds the SQL query string
function QueryBuilder:toSql()
    local sql = "SELECT " .. (self._distinct and "DISTINCT " or "") .. table.concat(self._selects, ", ") .. " FROM " .. self._table
    
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
    if adapter and adapter.escape_value then return adapter.escape_value(value) end
    if type(value) == "string" then
        return "'" .. value:gsub("'", "''"):gsub("\\", "\\\\"):gsub("\0", "") .. "'"
    elseif type(value) == "number" then return tostring(value)
    elseif type(value) == "boolean" then return value and "TRUE" or "FALSE"
    elseif value == nil then return "NULL"
    else return "'" .. tostring(value):gsub("'", "''") .. "'" end
end

-- Validates table/column names.
function QueryBuilder:_validateIdentifier(identifier)
    if not identifier:match("^[a-zA-Z0-9_.]+$") then error("Invalid identifier: " .. identifier) end
    return identifier
end

-- Executes a SELECT query and returns all results.
function QueryBuilder:get()
    local sql = self:toSql()
    
    -- 1. Application Cache (Level 2)
    if self._cache_ttl and _G.app and _G.app.cache then
        local cache_key = "query:" .. sql:gsub("[^%w]", "_")
        return _G.app.cache:fetch(cache_key, self._cache_ttl, function()
            local results, err = DBManager.query(sql)
            if err then error(err) end
            if self._model and results then return self._model:_hydrateAll(results) end
            return results
        end)
    end

    -- 2. Query Cache (Level 1)
    if DBManager.query_cache_enabled and DBManager.query_cache[sql] then return DBManager.query_cache[sql] end

    local results, err = DBManager.query(sql)
    if err then error(err) end

    local final_results = results
    if self._model and results then final_results = self._model:_hydrateAll(results) end
    if DBManager.query_cache_enabled then DBManager.query_cache[sql] = final_results end

    return final_results
end

-- Alias for get
function QueryBuilder:all() return self:get() end

-- Executes a SELECT query and returns the first result.
function QueryBuilder:first()
    self:limit(1)
    local results = self:get()
    return (results and #results > 0) and results[1] or nil
end

-- Executes a COUNT query.
function QueryBuilder:count()
    local original_selects = self._selects
    self._selects = {"COUNT(*) as count"}
    local sql = self:toSql(); self._selects = original_selects
    local results, err = DBManager.query(sql)
    if err then error(err) end
    return (results and results[1]) and tonumber(results[1].count) or 0
end

-- Calculation methods
function QueryBuilder:sum(column)
    local original_selects = self._selects
    self._selects = {string.format("SUM(%s) as val", column)}
    local res = self:first(); self._selects = original_selects
    return res and tonumber(res.val) or 0
end

function QueryBuilder:avg(column)
    local original_selects = self._selects
    self._selects = {string.format("AVG(%s) as val", column)}
    local res = self:first(); self._selects = original_selects
    return res and tonumber(res.val) or 0
end

function QueryBuilder:min(column)
    local original_selects = self._selects
    self._selects = {string.format("MIN(%s) as val", column)}
    local res = self:first(); self._selects = original_selects
    return res and res.val or nil
end

function QueryBuilder:max(column)
    local original_selects = self._selects
    self._selects = {string.format("MAX(%s) as val", column)}
    local res = self:first(); self._selects = original_selects
    return res and res.val or nil
end

-- Executes an INSERT query.
function QueryBuilder:insert(data)
    if not data or not next(data) then return nil, "No data" end
    local columns, values = {}, {}
    for k, v in pairs(data) do table.insert(columns, k); table.insert(values, self:_escapeValue(v)) end
    local sql = string.format("INSERT INTO %s (%s) VALUES (%s)", self._table, table.concat(columns, ", "), table.concat(values, ", "))
    return DBManager.insert(sql)
end

-- Executes an UPDATE query.
function QueryBuilder:update(data)
    if not data or not next(data) then return true end
    local sets = {}
    for k, v in pairs(data) do table.insert(sets, string.format("%s = %s", k, self:_escapeValue(v))) end
    local sql = string.format("UPDATE %s SET %s", self._table, table.concat(sets, ", ")) .. self:_buildWhere()
    local res, err = DBManager.update(sql)
    if err then error(err) end
    return (type(res) == "table" and res.affected) and res.affected >= 0 or res ~= nil
end

-- Executes a DELETE query.
function QueryBuilder:delete()
    local sql = "DELETE FROM " .. self._table .. self:_buildWhere()
    local res, err = DBManager.delete(sql)
    if err then error(err) end
    return (type(res) == "table" and res.affected) and res.affected >= 0 or res ~= nil
end

-- Static convenience methods
local M = {}
function M.table(table_name) return QueryBuilder.new():table(table_name) end
function M.raw(sql, bindings) return DBManager.query(sql, bindings) end
function M.query(sql, bindings) return M.raw(sql, bindings) end
M.new = QueryBuilder.new

return M
