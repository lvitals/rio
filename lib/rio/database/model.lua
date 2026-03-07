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
function Errors:add(attribute, message)
    if not self._errors[attribute] then self._errors[attribute] = {} end
    table.insert(self._errors[attribute], message)
end
function Errors:clear() self._errors = {} end
function Errors:any() return next(self._errors) ~= nil end
function Errors:all() return self._errors end
function Errors:on(attribute) return self._errors[attribute] or {} end
function Errors:size()
    local count = 0
    for _, errs in pairs(self._errors) do count = count + #errs end
    return count
end
function Errors:full_messages()
    local messages = {}
    for attr, errs in pairs(self._errors) do
        for _, msg in ipairs(errs) do
            if attr == "base" then table.insert(messages, msg)
            else table.insert(messages, attr:gsub("_", " "):gsub("^%l", string.upper) .. " " .. msg) end
        end
    end
    return messages
end

-- ==========================
-- MODEL CLASS
-- ==========================
local Model = {}
Model.__index = Model

-- SCOPE ENGINE: Proxy calls from ModelClass to QueryBuilder
local function add_query_proxy(ModelClass)
    local mt = getmetatable(ModelClass)
    
    mt.__index = function(t, k)
        -- 1. Check Model base methods (find, all, query, belongs_to, etc.)
        if Model[k] then return Model[k] end
        
        -- 2. Direct members (attributes like fillable, or Scopes)
        local member = rawget(t, k)
        if member ~= nil then
            if type(member) == "function" then
                return function(receiver, ...)
                    -- If called on the Class (Post:published()), receiver is the Class table (t)
                    if receiver == t then
                        local q = t:query()
                        return member(t, q, ...) or q
                    end
                    -- Otherwise it's an instance call (post:save())
                    return member(receiver, ...)
                end
            end
            return member
        end

        -- 3. QueryBuilder methods proxy (where, orderBy, limit, etc.)
        if type(QueryBuilder[k]) == "function" then
            return function(receiver, ...)
                local q = receiver:query()
                return q[k](q, ...)
            end
        end
        
        return nil
    end
end

function Model:extend(config)
    config = config or {}
    local ModelClass = {
        _relations = {},
        table_name = config.table_name,
        primary_key = config.primary_key or "id",
        timestamps = config.timestamps ~= false,
        fillable = config.fillable or {},
        hidden = config.hidden or {},
        attributes = config.attributes or {},
        validates = config.validates or {},
        soft_deletes = config.soft_deletes or false
    }
    ModelClass.class = ModelClass
    setmetatable(ModelClass, { __index = function(t, k) return Model[k] end })
    add_query_proxy(ModelClass)
    return ModelClass
end

function Model:new(attributes)
    attributes = attributes or {}
    local ModelClass = self
    local instance = {
        _attributes = attributes,
        _original = {},
        _exists = false,
        _relations_loaded = {},
        errors = Errors.new(),
        class = ModelClass
    }
    setmetatable(instance, {
        __index = function(t, k)
            local class_val = ModelClass[k]
            if class_val ~= nil then return class_val end
            local attr_val = t._attributes[k]
            if attr_val ~= nil then return attr_val end
            local rel_entry = ModelClass._relations and ModelClass._relations[k]
            if rel_entry and rel_entry.fn then
                if not t._relations_loaded[k] then t._relations_loaded[k] = rel_entry.fn(t) end
                return t._relations_loaded[k]
            end
            return nil
        end,
        __newindex = function(t, k, v)
            if k:sub(1,1) == "_" or k == "errors" or k == "class" then rawset(t, k, v)
            else t._attributes[k] = v end
        end,
        __tostring = function(t)
            local a = t._attributes; return tostring(a.name or a.title or a.username or a.id or "Model Instance")
        end
    })
    return instance
end

-- ==========================
-- RELATIONSHIP HELPERS (Class)
-- ==========================

local function get_related_model(model_path, name)
    local mod = package.loaded[model_path] or package.loaded[name]
    if not mod then local ok, res = pcall(require, model_path); if ok then mod = res end end
    return mod
end

function Model:belongs_to(name, options)
    if not self or type(self) == "string" then return end
    options = options or {}
    local path = options.model or ("app.models." .. name)
    self._relations[name] = {
        metadata = { type = "belongs_to", model_path = path, foreign_key = options.foreign_key, primary_key = options.primary_key, dependent = options.dependent },
        fn = function(inst)
            local Rel = get_related_model(path, name); if not Rel then error("Could not load model: " .. path) end
            return inst:belongsTo(Rel, options.foreign_key, options.primary_key, name)
        end
    }
end

function Model:has_many(name, options)
    if not self or type(self) == "string" then return end
    options = options or {}
    local singular = string_utils.singularize(name)
    local path = options.model or ("app.models." .. singular)
    local ModelClass = self
    self._relations[name] = {
        metadata = { type = "has_many", model_path = path, foreign_key = options.foreign_key, local_key = options.local_key, dependent = options.dependent, through = options.through, source = options.source or singular },
        fn = function(inst)
            if options.through then
                local TargetModel = get_related_model(path, singular)
                local through_rel = ModelClass._relations[options.through]; if not through_rel then error("Through not found: " .. options.through) end
                local through_meta = through_rel.metadata
                local ThroughModel = get_related_model(through_meta.model_path, string_utils.singularize(options.through))
                local target_fk = (options.source or singular) .. "_id"
                local parent_fk = through_meta.foreign_key or (string_utils.singularize(ModelClass.table_name or "") .. "_id")
                return TargetModel:query():select(TargetModel.table_name .. ".*")
                    :join(ThroughModel.table_name, ThroughModel.table_name .. "." .. target_fk, "=", TargetModel.table_name .. ".id")
                    :where(ThroughModel.table_name .. "." .. parent_fk, inst.id)
            else
                local Rel = get_related_model(path, singular); if not Rel then error("Could not load model: " .. path) end
                return inst:hasMany(Rel, options.foreign_key, options.local_key)
            end
        end
    }
end

function Model:has_one(name, options)
    if not self or type(self) == "string" then return end
    options = options or {}
    local path = options.model or ("app.models." .. name)
    self._relations[name] = {
        metadata = { type = "has_one", model_path = path, foreign_key = options.foreign_key, local_key = options.local_key, dependent = options.dependent },
        fn = function(inst)
            local Rel = get_related_model(path, name); if not Rel then error("Could not load model: " .. path) end
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
    if type(mc) == "table" and mc.table_name then q:table(mc.table_name) end
    if type(mc) == "table" and mc.soft_deletes then q:whereNull("deleted_at") end
    return q
end

function Model:find(id) return self:query():where(self.primary_key or "id", id):first() end
function Model:all() return self:query():get() end
function Model:first() return self:query():first() end
function Model:last() return self:query():orderBy(self.primary_key or "id", "DESC"):first() end
function Model:find_by(attrs) local q = self:query(); for k, v in pairs(attrs) do q:where(k, v) end; return q:first() end
function Model:find_or_create_by(attrs) local r = self:find_by(attrs); if r then return r end; return self:create(attrs) end
function Model:first_or_create(attrs) return self:find_or_create_by(attrs) end
function Model:exists(conds)
    local q = self:query()
    if type(conds) == "table" then for k, v in pairs(conds) do q:where(k, v) end
    elseif conds ~= nil then q:where(self.primary_key or "id", conds) end
    return q:count() > 0
end

function Model:where(c, o, v) return self:query():where(c, o, v) end
function Model:limit(n) return self:query():limit(n) end
function Model:order(c, d) return self:query():orderBy(c, d) end

-- Aggregations
function Model:count() return self:query():count() end
function Model:avg(c) return self:query():avg(c) end
function Model:sum(c) return self:query():sum(c) end
function Model:min(c) return self:query():min(c) end
function Model:max(c) return self:query():max(c) end

function Model:destroy_all() local items = self:all(); local count = 0; for _, i in ipairs(items) do if i:delete() then count = count + 1 end end; return count end
function Model:delete_all() return self:query():delete() end
function Model:raw(s, b) return QueryBuilder.raw(s, b) end

function Model.transaction(callback)
    local DB = require("rio.database.manager"); DB.begin()
    local ok, res = pcall(callback)
    if ok then DB.commit(); return res else DB.rollback(); error(res) end
end

-- ==========================
-- CRUD METHODS
-- ==========================

function Model:save()
    if not self:validate() then return false end
    if self.before_save then self:before_save() end
    if self._exists then return self:_update() else return self:_create() end
end

function Model:create(attrs) local inst = self:new(attrs); local ok = inst:save(); return ok and inst or nil, inst end
function Model:update(attrs)
    if type(attrs) ~= "table" then return false, "Attributes must be a table" end
    for k, v in pairs(attrs) do self._attributes[k] = v end
    return self:save()
end

function Model:delete()
    if not self._exists then error("Cannot delete non-existent model") end
    self:_handleDependentAssociations()
    if self.before_delete then self.before_delete(self) end
    local id = self[self.primary_key or "id"]
    local ok
    if self.soft_deletes then
        self.deleted_at = os.date("%Y-%m-%d %H:%M:%S")
        ok = self:query():where(self.primary_key or "id", id):update({deleted_at = self.deleted_at})
    else
        ok = self:query():where(self.primary_key or "id", id):delete()
    end
    if ok then self._exists = false; if self.after_delete then self.after_delete(self) end end
    return ok
end

function Model:_handleDependentAssociations()
    local mc = self.class; if not mc._relations then return end
    for name, rel in pairs(mc._relations) do
        local meta = rel.metadata
        if meta and meta.dependent then
            local assoc = self[name]
            if assoc then
                if meta.dependent == "destroy" then
                    if meta.type == "has_many" then local children = assoc:get(); for _, c in ipairs(children) do c:delete() end else assoc:delete() end
                elseif meta.dependent == "delete_all" then
                    if meta.type == "has_many" then assoc:delete() else assoc:query():delete() end
                end
            end
        end
    end
end

function Model:_create()
    if self.before_create then self.before_create(self) end
    if self.timestamps then self.created_at = os.date("%Y-%m-%d %H:%M:%S"); self.updated_at = self.created_at end
    local data = self:_filterAttributes(self._attributes)
    local id = self:query():insert(data)
    if id then
        self[self.primary_key or "id"] = id; self._exists = true; self._original = self:_copy(self._attributes)
        if self.after_create then self.after_create(self) end
        return true
    end
    return false
end

function Model:_update()
    if self.before_update then self.before_update(self) end
    if self.timestamps then self.updated_at = os.date("%Y-%m-%d %H:%M:%S") end
    local id = self[self.primary_key or "id"]
    local data = self:_filterAttributes(self._attributes); data[self.primary_key or "id"] = nil
    if self:query():where(self.primary_key or "id", id):update(data) then
        self._original = self:_copy(self._attributes); if self.after_update then self.after_update(self) end
        return true
    end
    return false
end

-- ==========================
-- RELATIONSHIPS (Instance)
-- ==========================

function Model:hasMany(Rel, fk, lk)
    local lk_field = lk or self.primary_key or "id"
    local fk_field = fk or (string_utils.singularize(self.class.table_name or "") .. "_id")
    local val = self[lk_field]
    local q = Rel:query():where(fk_field, val)
    function q:build(a) a = a or {}; a[fk_field] = val; return Rel:new(a) end
    function q:create(a) local c = self:build(a); c:save(); return c end
    return q
end
function Model:hasOne(Rel, fk, lk) 
    local lk_field = lk or self.primary_key or "id"
    local fk_field = fk or (string_utils.singularize(self.class.table_name or "") .. "_id")
    return Rel:query():where(fk_field, self[lk_field]):first() 
end
function Model:belongsTo(Rel, fk, owner_key, name) 
    local fk_field = fk or (name and name .. "_id") or (string_utils.singularize(Rel.table_name or "") .. "_id")
    return Rel:find(self[fk_field]) 
end

-- ==========================
-- INTERNAL
-- ==========================

function Model:_hydrate(data) local inst = self:new(data); inst._original = self:_copy(data); inst._exists = true; return inst end
function Model:_hydrateAll(results) local instances = {}; for _, row in ipairs(results or {}) do table.insert(instances, self:_hydrate(row)) end; return instances end

function Model:validate()
    self.errors:clear(); if not self.validates then return true end
    for field, rules in pairs(self.validates) do
        -- Handle custom validation functions
        if type(rules) == "function" then
            rules(self)
        else
            local v = self[field]
            if type(rules) == "string" then rules = { [rules] = true } end
            if rules.presence and (v == nil or v == "" or (type(v) == "string" and v:match("^%s*$"))) then self.errors:add(field, "can't be blank") end
            if rules.uniqueness and v then
                local q = self:query():where(field, v); if self._exists then q:where(self.primary_key or "id", "!=", self[self.primary_key or "id"]) end
                if q:first() then self.errors:add(field, "has already been taken") end
            end
            if rules.format and v then
                local r = rules.format
                if r.with and not tostring(v):match(r.with) then self.errors:add(field, r.message or "is invalid") end
            end
            if rules.length and v then
                local len = #tostring(v); local r = rules.length
                if r.minimum and len < r.minimum then self.errors:add(field, r.message or "is too short") end
                if r.maximum and len > r.maximum then self.errors:add(field, r.message or "is too long") end
            end
            if rules.numericality and v then
                local num = tonumber(v); local r = rules.numericality
                if not num then self.errors:add(field, r.message or "is not a number")
                else
                    if r.only_integer and math.floor(num) ~= num then self.errors:add(field, r.message or "must be an integer") end
                    if r.greater_than and num <= r.greater_than then self.errors:add(field, r.message or "must be greater than " .. r.greater_than) end
                    if r.less_than and num >= r.less_than then self.errors:add(field, r.message or "must be less than " .. r.less_than) end
                end
            end
        end
    end
    return not self.errors:any()
end

function Model:_filterAttributes(data)
    local filtered = {}; local allowed = {}
    for _, f in ipairs(self.class.fillable or {}) do allowed[f] = true end
    if not next(allowed) then
        for k, v in pairs(data) do if type(k) == "string" and k:sub(1,1) ~= "_" and k ~= "errors" and k ~= "class" then filtered[k] = v end end
    else
        for k, v in pairs(data) do if allowed[k] or k == "created_at" or k == "updated_at" then filtered[k] = v end end
    end
    return filtered
end

function Model:_copy(t) local c = {}; for k,v in pairs(t) do c[k]=v end; return c end
function Model:toTable()
    local data = {}; local hidden = {}
    for _, h in ipairs(self.class.hidden or {}) do hidden[h] = true end
    for k, v in pairs(self._attributes) do if not hidden[k] then data[k] = v end end
    return data
end
function Model:toJSON() return self:toTable() end
function Model:toArray() return self:toTable() end

return Model
