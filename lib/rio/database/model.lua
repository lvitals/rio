-- rio/lib/rio/database/model.lua
-- Active Record ORM for the Rio Framework

local QueryBuilder = require("rio.database.query_builder")
local string_utils = require("rio.utils.string")

-- ==========================
-- ERRORS CLASS
-- ==========================
local Errors = {}
Errors.__index = Errors
function Errors.new() return setmetatable({ _errors = {} }, Errors) end
function Errors:add(attr, msg) 
    if not self._errors[attr] then self._errors[attr] = {} end
    table.insert(self._errors[attr], msg)
end
function Errors:clear() self._errors = {} end
function Errors:any() return next(self._errors) ~= nil end
function Errors:all() return self._errors end
function Errors:on(attr) return self._errors[attr] or {} end
function Errors:size()
    local count = 0
    for _, errs in pairs(self._errors) do count = count + #errs end
    return count
end
function Errors:full_messages()
    local msgs = {}
    for attr, errs in pairs(self._errors) do
        for _, m in ipairs(errs) do
            local label = attr == "base" and "" or attr:gsub("_", " "):gsub("^%l", string.upper) .. " "
            table.insert(msgs, label .. m)
        end
    end
    return msgs
end

-- ==========================
-- MODEL BASE CLASS
-- ==========================
local Model = {}

function Model:extend(config)
    local methods = {
        _relations = {},
        table_name = config and config.table_name,
        primary_key = (config and config.primary_key) or "id",
        timestamps = not (config and config.timestamps == false),
        fillable = (config and config.fillable) or {},
        hidden = (config and config.hidden) or {},
        validates = (config and config.validates) or {},
        soft_deletes = (config and config.soft_deletes) or false,
        per_page = (config and config.per_page) or 5
    }
    
    local ModelClass = setmetatable({ _methods = methods }, {
        __index = function(t, k)
            local member = methods[k]
            if member ~= nil then
                if type(member) == "function" then
                    return function(receiver, ...)
                        if receiver == t then 
                            local q = t:query()
                            return member(t, q, ...) or q
                        end
                        return member(receiver, ...)
                    end
                end
                return member
            end
            if Model[k] then return Model[k] end
            if type(QueryBuilder[k]) == "function" then
                return function(receiver, ...)
                    local q = (receiver == t) and t:query() or receiver
                    return q[k](q, ...)
                end
            end
            return nil
        end,
        __newindex = function(t, k, v) methods[k] = v end
    })
    
    ModelClass.class = ModelClass
    return ModelClass
end

function Model:new(attributes)
    local ModelClass = self
    local instance = {
        _attributes = attributes or {},
        _original = {},
        _exists = false,
        _relations_loaded = {},
        errors = Errors.new(),
        class = ModelClass
    }
    
    setmetatable(instance, {
        __index = function(t, k)
            local attr = t._attributes[k]
            if attr ~= nil then return attr end
            local class_val = ModelClass[k]
            if class_val ~= nil then return class_val end
            local rel = ModelClass._relations and ModelClass._relations[k]
            if rel and rel.fn then
                if not t._relations_loaded[k] then t._relations_loaded[k] = rel.fn(t) end
                return t._relations_loaded[k]
            end
            return nil
        end,
        __newindex = function(t, k, v)
            if k:sub(1,1) == "_" or k == "errors" or k == "class" then rawset(t, k, v)
            else t._attributes[k] = v end
        end,
        __tostring = function(t)
            local a = t._attributes
            return tostring(a.name or a.title or a.username or a.id or "Model Instance")
        end
    })
    return instance
end

-- ==========================
-- RELATIONSHIP HELPERS
-- ==========================

local function get_related_model(path, name)
    -- 1. Check if already loaded by path or name
    local mod = package.loaded[path] or package.loaded[name]
    if mod then return mod end

    -- 2. Try to require it
    local ok, res = pcall(require, path)
    if ok then return res end

    -- 3. Look in global scope (useful for tests)
    local camel_name = string_utils.camel_case(name)
    if _G[camel_name] then return _G[camel_name] end
    if _G[name] then return _G[name] end

    return nil
end

function Model:belongs_to(name, options)
    options = options or {}
    local path = options.model_path or ("app.models." .. name)
    self._relations[name] = {
        metadata = { type = "belongs_to", model_path = path, foreign_key = options.foreign_key, primary_key = options.primary_key, dependent = options.dependent },
        fn = function(inst)
            local Rel = (type(options.model) == "table") and options.model or get_related_model(path, name)
            return inst:belongsTo(Rel, options.foreign_key, options.primary_key, name)
        end
    }
end

function Model:has_many(name, options)
    options = options or {}
    local singular = string_utils.singularize(name)
    local path = options.model_path or ("app.models." .. singular)
    local ModelClass = self
    self._relations[name] = {
        metadata = { type = "has_many", model_path = path, foreign_key = options.foreign_key, through = options.through, source = options.source or singular, dependent = options.dependent },
        fn = function(inst)
            if options.through then
                local trel = ModelClass._relations[options.through]
                local Target = (type(options.model) == "table") and options.model or get_related_model(path, singular)
                local ThroughModel = get_related_model(trel.metadata.model_path, string_utils.singularize(options.through))
                local tfk = (options.source or singular) .. "_id"
                local pfk = (string_utils.singularize(ModelClass.table_name or "") .. "_id")
                return Target:query():select(Target.table_name .. ".*")
                    :join(ThroughModel.table_name, ThroughModel.table_name .. "." .. tfk, "=", Target.table_name .. ".id")
                    :where(ThroughModel.table_name .. "." .. pfk, inst.id)
            end
            local Rel = (type(options.model) == "table") and options.model or get_related_model(path, singular)
            return inst:hasMany(Rel, options.foreign_key, options.local_key)
        end
    }
end

function Model:has_one(name, options)
    options = options or {}
    local path = options.model_path or ("app.models." .. name)
    self._relations[name] = {
        metadata = { type = "has_one", model_path = path, foreign_key = options.foreign_key, dependent = options.dependent },
        fn = function(inst)
            local Rel = (type(options.model) == "table") and options.model or get_related_model(path, name)
            return inst:hasOne(Rel, options.foreign_key, options.local_key)
        end
    }
end

-- ==========================
-- QUERY METHODS
-- ==========================

function Model:query()
    local mc = self.class or self
    local q = QueryBuilder.new(mc)
    if mc.table_name then q:table(mc.table_name) end
    if mc.soft_deletes then q:whereNull("deleted_at") end
    return q
end

function Model:find(id) return self:query():where(self.primary_key or "id", id):first() end
function Model:all() return self:query():get() end
function Model:first() return self:query():first() end
function Model:last() return self:query():orderBy(self.primary_key or "id", "DESC"):first() end
function Model:find_by(attrs) local q = self:query(); for k,v in pairs(attrs) do q:where(k,v) end; return q:first() end
function Model:find_or_create_by(attrs) local r = self:find_by(attrs); return r or self:create(attrs) end
function Model:first_or_create(attrs) return self:find_or_create_by(attrs) end

function Model:exists(conds)
    local q = self:query()
    if type(conds) == "table" then for k,v in pairs(conds) do q:where(k,v) end
    elseif conds ~= nil then q:where(self.primary_key or "id", conds) end
    return q:count() > 0
end

function Model:where(c, o, v) return self:query():where(c, o, v) end
function Model:limit(n) return self:query():limit(n) end
function Model:order(c, d) return self:query():orderBy(c, d) end

function Model:count() return self:query():count() end
function Model:sum(c) return self:query():sum(c) end
function Model:avg(c) return self:query():avg(c) end
function Model:min(c) return self:query():min(c) end
function Model:max(c) return self:query():max(c) end

function Model:delete_all() return self:query():delete() end
function Model:destroy_all() for _, item in ipairs(self:all()) do item:delete() end end
function Model:raw(s, b) return QueryBuilder.raw(s, b) end

function Model.transaction(cb)
    local DBM = require("rio.database.manager"); DBM.begin()
    local ok, res = pcall(cb)
    if ok then DBM.commit(); return res else DBM.rollback(); error(res) end
end

-- ==========================
-- CRUD
-- ==========================

function Model:save()
    if not self:validate() then return false end
    if self.before_save then self:before_save() end
    return self._exists and self:_update() or self:_create() end

function Model:create(attrs)
    local inst = self:new(attrs)
    local ok = inst:save()
    return ok and inst or nil, inst
end

function Model:update(attrs)
    if type(attrs) ~= "table" then return false end
    for k, v in pairs(attrs) do self._attributes[k] = v end
    return self:save()
end

function Model:delete()
    if not self._exists then return false end
    
    -- Handle dependent deletion
    local relations = self.class._relations or {}
    for name, rel in pairs(relations) do
        if rel.metadata and rel.metadata.dependent == "destroy" then
            local associated = self[name]
            if associated then
                if rel.metadata.type == "has_many" then
                    -- For has_many, associated is a query builder, we need to get results
                    local items = type(associated) == "table" and associated.get and associated:get() or associated
                    if type(items) == "table" then
                        for _, item in ipairs(items) do
                            if type(item) == "table" and item.delete then item:delete() end
                        end
                    end
                elseif type(associated) == "table" and associated.delete then
                    associated:delete()
                end
            end
        end
    end

    local id = self[self.primary_key or "id"]
    local ok
    if self.class.soft_deletes then
        ok = self:query():where(self.primary_key or "id", id):update({deleted_at = os.date("%Y-%m-%d %H:%M:%S")})
    else
        ok = self:query():where(self.primary_key or "id", id):delete()
    end
    if ok then self._exists = false end
    return ok
end

function Model:_create()
    if self.before_create then self.before_create(self) end
    if self.class.timestamps then self.created_at = os.date("%Y-%m-%d %H:%M:%S"); self.updated_at = self.created_at end
    local data = self:_filterAttributes(self._attributes)
    local id = self:query():insert(data)
    if id then self[self.primary_key or "id"] = id; self._exists = true; self._original = self:_copy(self._attributes); return true end
    return false
end

function Model:_update()
    if self.before_update then self.before_update(self) end
    if self.class.timestamps then self.updated_at = os.date("%Y-%m-%d %H:%M:%S") end
    local data = self:_filterAttributes(self._attributes); data[self.primary_key or "id"] = nil
    if self:query():where(self.primary_key or "id", self.id):update(data) then self._original = self:_copy(self._attributes); return true end
    return false
end

-- ==========================
-- INSTANCE HELPERS
-- ==========================

function Model:hasMany(Rel, fk, lk)
    if not Rel then error("Association Error: Could not resolve related Model. Ensure the model is required or correctly named.") end
    local lk_field = lk or self.primary_key or "id"
    local fk_field = fk or (string_utils.singularize(self.class.table_name or "") .. "_id")
    local val = self[lk_field]
    local q = Rel:query():where(fk_field, val)
    function q:build(a) a = a or {}; a[fk_field] = val; return Rel:new(a) end
    function q:create(a) local c = self:build(a); c:save(); return c end
    return q
end

function Model:hasOne(Rel, fk, lk)
    if not Rel then error("Association Error: Could not resolve related Model. Ensure the model is required or correctly named.") end
    local fk_field = fk or (string_utils.singularize(self.class.table_name or "") .. "_id")
    return Rel:query():where(fk_field, self[lk or self.primary_key or "id"]):first()
end

function Model:belongsTo(Rel, fk, pk, name)
    if not Rel then error("Association Error: Could not resolve related Model. Ensure the model is required or correctly named.") end
    local fk_field = fk or (name and name .. "_id") or (string_utils.singularize(Rel.table_name or "") .. "_id")
    return Rel:find(self[fk_field])
end

-- ==========================
-- INTERNAL
-- ==========================

function Model:_hydrate(data) local inst = self:new(data); inst._original = self:_copy(data); inst._exists = true; return inst end
function Model:_hydrateAll(res) local list = {}; for _, row in ipairs(res or {}) do table.insert(list, self:_hydrate(row)) end; return list end

function Model:validate()
    self.errors:clear(); if not self.validates then return true end
    for f, rules in pairs(self.validates) do
        if type(rules) == "function" then rules(self)
        else
            local v = self[f]
            if type(rules) == "string" then rules = { [rules] = true } end
            if rules.presence and (v == nil or v == "" or (type(v) == "string" and v:match("^%s*$"))) then self.errors:add(f, "can't be blank") end
            if rules.uniqueness and v then
                local q = self:query():where(f, v); if self._exists then q:where(self.primary_key or "id", "!=", self.id) end
                if q:first() then self.errors:add(f, "has already been taken") end
            end
            if rules.format and v then
                local r = rules.format
                if r.with and not tostring(v):match(r.with) then self.errors:add(f, r.message or "is invalid") end
            end
            if rules.length and v then
                local len = #tostring(v); local r = rules.length
                if r.minimum and len < r.minimum then self.errors:add(f, r.message or "is too short") end
                if r.maximum and len > r.maximum then self.errors:add(f, r.message or "is too long") end
            end
            if rules.numericality and v then
                local num = tonumber(v); local r = rules.numericality
                if not num then self.errors:add(f, r.message or "is not a number")
                else
                    if r.only_integer and math.floor(num) ~= num then self.errors:add(f, r.message or "must be an integer") end
                    if r.greater_than and num <= r.greater_than then self.errors:add(f, r.message or "must be greater than " .. r.greater_than) end
                    if r.less_than and num >= r.less_than then self.errors:add(f, r.message or "must be less than " .. r.less_than) end
                end
            end
        end
    end
    return not self.errors:any()
end

function Model:_filterAttributes(data)
    local filtered = {}; local mc = self.class
    local allowed = {}; for _, f in ipairs(mc.fillable or {}) do allowed[f] = true end
    allowed.created_at = true; allowed.updated_at = true; allowed.deleted_at = true; allowed.published_at = true
    if not next(allowed) or #mc.fillable == 0 then
        for k, v in pairs(data) do if type(k) == "string" and k:sub(1,1) ~= "_" and k ~= "errors" and k ~= "class" then filtered[k] = v end end
    else
        for k, v in pairs(data) do if allowed[k] then filtered[k] = v end end
    end
    return filtered
end

function Model:_copy(t) local c = {}; for k,v in pairs(t) do c[k]=v end; return c end
function Model:toTable()
    local data = {}; local hidden = {}; for _, h in ipairs(self.class.hidden or {}) do hidden[h] = true end
    for k, v in pairs(self._attributes) do if not hidden[k] then data[k] = v end end
    return data
end
function Model:toJSON() return self:toTable() end
function Model:toArray() return self:toTable() end

return Model
