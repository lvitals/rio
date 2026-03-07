-- rio/lib/rio/database/query_builder.lua
-- SQL Query Builder inspired by Laravel/Eloquent.

local QueryBuilder = {}
QueryBuilder.__index = QueryBuilder

local DBManager = require("rio.database.manager")
local string_utils = require("rio.utils.string")

function QueryBuilder.new(model)
    local qb = setmetatable({}, {
        __index = function(t, k)
            -- 1. Check QueryBuilder methods first
            if QueryBuilder[k] then return QueryBuilder[k] end
            
            -- 2. Scopes Logic: Delegate to Model's proxy
            -- If the model has it, the proxy will handle the injection
            if model and type(model) == "table" and model[k] then
                return function(_, ...)
                    -- Call the proxy function on 't' (the QueryBuilder)
                    return model[k](t, ...)
                end
            end
            return nil
        end,
        __tostring = function(q)
            local table_name = rawget(q, "_table") or "unknown"
            local selects = rawget(q, "_selects") or {"*"}
            return string.format("Query(%s) { select: [%s] }", table_name, table.concat(selects, ", "))
        end
    })
    
    rawset(qb, "_model", model)
    if type(model) == "table" then
        rawset(qb, "_table", model.table_name or model._table or nil)
    end
    rawset(qb, "_wheres", {})
    rawset(qb, "_selects", {"*"})
    rawset(qb, "_joins", {})
    rawset(qb, "_orderBy", {})
    rawset(qb, "_limit", nil)
    rawset(qb, "_offset", nil)
    rawset(qb, "_cache_ttl", nil)
    rawset(qb, "_distinct", false)
    
    return qb
end

function QueryBuilder:cache(ttl) self._cache_ttl = ttl or 3600; return self end
function QueryBuilder:distinct() self._distinct = true; return self end
function QueryBuilder:table(name) self._table = self:_validateIdentifier(name); return self end
function QueryBuilder:select(...) local args = {...}; if #args > 0 then self._selects = args end; return self end

function QueryBuilder:where(column, operator, value)
    if type(column) == "function" then
        local nested_qb = QueryBuilder.new(self._model)
        column(nested_qb)
        table.insert(self._wheres, { type = "AND", nested = nested_qb._wheres })
        return self
    end
    if value == nil and operator ~= nil then value = operator; operator = "=" end
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
    if value == nil and operator ~= nil then value = operator; operator = "=" end
    table.insert(self._wheres, { column = column, operator = operator, value = value, type = "OR" })
    return self
end

function QueryBuilder:whereHas(name, callback) return self:_addWhereHas(name, callback, "AND") end
function QueryBuilder:orWhereHas(name, callback) return self:_addWhereHas(name, callback, "OR") end

function QueryBuilder:_addWhereHas(name, callback, boolean_type)
    if not self._model or not self._model._relations or not self._model._relations[name] then
        error("Relation '" .. tostring(name) .. "' not defined on model")
    end
    local rel_meta = self._model._relations[name].metadata
    local RelatedModel = require(rel_meta.model_path)
    local sub_qb = RelatedModel:query():select("1")
    
    if callback then callback(sub_qb) end
    
    if rel_meta.through then
        local through_rel = self._model._relations[rel_meta.through]
        local through_meta = through_rel.metadata
        local ThroughModel = require(through_meta.model_path)
        local target_fk = (rel_meta.source or string_utils.singularize(name)) .. "_id"
        local parent_fk = through_meta.foreign_key or (string_utils.singularize(self._model.table_name) .. "_id")
        
        sub_qb:join(ThroughModel.table_name, ThroughModel.table_name .. "." .. target_fk, "=", RelatedModel.table_name .. ".id")
        sub_qb:whereColumn(ThroughModel.table_name .. "." .. parent_fk, "=", self._table .. ".id")
    elseif rel_meta.type == "belongs_to" then
        sub_qb:whereColumn(RelatedModel.table_name .. "." .. (rel_meta.primary_key or "id"), "=", self._table .. "." .. (rel_meta.foreign_key or (name .. "_id")))
    else
        sub_qb:whereColumn(RelatedModel.table_name .. "." .. (rel_meta.foreign_key or (string_utils.singularize(self._model.table_name) .. "_id")), "=", self._table .. "." .. (rel_meta.primary_key or "id"))
    end
    
    table.insert(self._wheres, { type = boolean_type, raw = "EXISTS (" .. sub_qb:toSql() .. ")" })
    return self
end

function QueryBuilder:whereColumn(first, operator, second) table.insert(self._wheres, { type = "AND", raw = string.format("%s %s %s", first, operator, second) }); return self end
function QueryBuilder:whereIn(column, values) table.insert(self._wheres, { column = column, operator = "IN", value = values, type = "AND" }); return self end
function QueryBuilder:whereNull(column) table.insert(self._wheres, { column = column, operator = "IS NULL", value = nil, type = "AND" }); return self end
function QueryBuilder:whereNotNull(column) table.insert(self._wheres, { column = column, operator = "IS NOT NULL", value = nil, type = "AND" }); return self end

function QueryBuilder:join(tbl, f, op, s) if not s then s = op; op = "=" end; table.insert(self._joins, { type = "INNER", table = tbl, first = f, operator = op, second = s }); return self end
function QueryBuilder:leftJoin(tbl, f, op, s) if not s then s = op; op = "=" end; table.insert(self._joins, { type = "LEFT", table = tbl, first = f, operator = op, second = s }); return self end
function QueryBuilder:orderBy(column, direction) table.insert(self._orderBy, { column = column, direction = direction or "ASC" }); return self end
function QueryBuilder:limit(num) self._limit = num; return self end
function QueryBuilder:offset(num) self._offset = num; return self end
function QueryBuilder:skip(num) return self:offset(num) end
function QueryBuilder:take(num) return self:limit(num) end
function QueryBuilder:paginate(p, pp) p = tonumber(p) or 1; pp = tonumber(pp) or 15; self:limit(pp):offset((p - 1) * pp); return self end

function QueryBuilder:_buildWhere(wheres_list)
    local target = wheres_list or self._wheres
    if #target == 0 then return "" end
    local where_clauses = {}
    for i, w in ipairs(target) do
        local clause
        local boolean_type = (i == 1 and "" or w.type .. " ")
        if w.nested then clause = "(" .. self:_buildWhere(w.nested) .. ")"
        elseif w.raw then clause = w.raw
        elseif w.operator == "IN" then
            local vs = {}; for _, v in ipairs(w.value) do table.insert(vs, self:_escapeValue(v)) end
            clause = string.format("%s IN (%s)", w.column, table.concat(vs, ", "))
        elseif w.operator == "IS NULL" or w.operator == "IS NOT NULL" then clause = string.format("%s %s", w.column, w.operator)
        else clause = string.format("%s %s %s", w.column, w.operator, self:_escapeValue(w.value)) end
        table.insert(where_clauses, boolean_type .. clause)
    end
    local final = table.concat(where_clauses, " ")
    return wheres_list and final or " WHERE " .. final
end

function QueryBuilder:toSql()
    local sql = "SELECT " .. (self._distinct and "DISTINCT " or "") .. table.concat(self._selects, ", ") .. " FROM " .. self._table
    for _, join in ipairs(self._joins) do sql = sql .. string.format(" %s JOIN %s ON %s %s %s", join.type, join.table, join.first, join.operator, join.second) end
    sql = sql .. self:_buildWhere()
    if #self._orderBy > 0 then
        local orders = {}; for _, order in ipairs(self._orderBy) do table.insert(orders, order.column .. " " .. order.direction) end
        sql = sql .. " ORDER BY " .. table.concat(orders, ", ")
    end
    if self._limit then sql = sql .. " LIMIT " .. self._limit end
    if self._offset then sql = sql .. " OFFSET " .. self._offset end
    return sql
end

function QueryBuilder:_escapeValue(value)
    local adapter = DBManager.get_adapter()
    if adapter and adapter.escape_value then return adapter.escape_value(value) end
    if type(value) == "string" then return "'" .. value:gsub("'", "''") .. "'"
    elseif type(value) == "number" then return tostring(value)
    elseif type(value) == "boolean" then return value and "TRUE" or "FALSE"
    elseif value == nil then return "NULL"
    else return "'" .. tostring(value):gsub("'", "''") .. "'" end
end

function QueryBuilder:_validateIdentifier(id) if not id:match("^[a-zA-Z0-9_.]+$") then error("Invalid identifier: " .. id) end return id end

function QueryBuilder:get()
    local sql = self:toSql()
    if self._cache_ttl and _G.app and _G.app.cache then
        local key = "query:" .. sql:gsub("[^%w]", "_")
        return _G.app.cache:fetch(key, self._cache_ttl, function()
            local results, err = DBManager.query(sql); if err then error(err) end
            if self._model and results then return self._model:_hydrateAll(results) end
            return results
        end)
    end
    if DBManager.query_cache_enabled and DBManager.query_cache[sql] then return DBManager.query_cache[sql] end
    local results, err = DBManager.query(sql); if err then error(err) end
    local final_results = results
    if self._model and results then final_results = self._model:_hydrateAll(results) end
    if DBManager.query_cache_enabled then DBManager.query_cache[sql] = final_results end
    return final_results
end

function QueryBuilder:all() return self:get() end
function QueryBuilder:first() self:limit(1); local results = self:get(); return (results and #results > 0) and results[1] or nil end

function QueryBuilder:count()
    local original = self._selects; self._selects = {"COUNT(*) as count"}
    local sql = self:toSql(); self._selects = original
    local results, err = DBManager.query(sql); if err then error(err) end
    return (results and results[1]) and tonumber(results[1].count) or 0
end

function QueryBuilder:sum(col) self._selects = {string.format("SUM(%s) as val", col)}; local res = self:first(); return res and tonumber(res.val) or 0 end
function QueryBuilder:avg(col) self._selects = {string.format("AVG(%s) as val", col)}; local res = self:first(); return res and tonumber(res.val) or 0 end
function QueryBuilder:min(col) self._selects = {string.format("MIN(%s) as val", col)}; local res = self:first(); return res and res.val or nil end
function QueryBuilder:max(col) self._selects = {string.format("MAX(%s) as val", col)}; local res = self:first(); return res and res.val or nil end

function QueryBuilder:insert(data)
    if not data or not next(data) then return nil, "No data" end
    local columns, values = {}, {}
    for k, v in pairs(data) do table.insert(columns, k); table.insert(values, self:_escapeValue(v)) end
    local sql = string.format("INSERT INTO %s (%s) VALUES (%s)", self._table, table.concat(columns, ", "), table.concat(values, ", "))
    return DBManager.insert(sql)
end

function QueryBuilder:update(data)
    if not data or not next(data) then return true end
    local sets = {}
    for k, v in pairs(data) do table.insert(sets, string.format("%s = %s", k, self:_escapeValue(v))) end
    local sql = string.format("UPDATE %s SET %s", self._table, table.concat(sets, ", ")) .. self:_buildWhere()
    local res, err = DBManager.update(sql); if err then error(err) end
    return (type(res) == "table" and res.affected) and res.affected >= 0 or res ~= nil
end

function QueryBuilder:delete()
    local sql = "DELETE FROM " .. self._table .. self:_buildWhere()
    local res, err = DBManager.delete(sql); if err then error(err) end
    return (type(res) == "table" and res.affected) and res.affected >= 0 or res ~= nil
end

local M = {}
M.table = function(table_name) return QueryBuilder.new():table(table_name) end
M.raw = function(sql, bindings) return DBManager.query(sql, bindings) end
M.query = function(sql, bindings) return M.raw(sql, bindings) end
M.new = QueryBuilder.new
return M
