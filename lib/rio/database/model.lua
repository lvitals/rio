-- rio/lib/rio/database/model.lua
-- Active Record ORM for the Rio Framework

local QueryBuilder = require("rio.database.query_builder")
local string_utils = require("rio.utils.string")

-- ==========================
-- ERRORS CLASS
-- ==========================
local Errors = {}
Errors.__index = Errors

function Errors.new()
    return setmetatable({ _errors = {} }, Errors)
end

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
    local original_index = mt.__index
    
    mt.__index = function(t, k)
        -- 1. Check Model base methods (find, all, query, belongs_to, has_many, etc.)
        if Model[k] then return Model[k] end
        
        -- 2. Check for raw members first (attributes like fillable, table_name, etc.)
        local raw_val = rawget(t, k)
        if raw_val ~= nil then return raw_val end

        -- 3. Scopes Logic: Methods defined directly on the ModelClass (Scopes)
        -- We already checked for raw_val, but if it was nil, it might be a function 
        -- added later. However, Scopes are usually functions.
        -- Let's check QueryBuilder methods specifically.
        if type(QueryBuilder[k]) == "function" then
            return function(self, ...)
                local q = (getmetatable(self) == mt) and self:query() or self
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
    
    setmetatable(ModelClass, { 
        __index = function(t, k)
            return Model[k]
        end 
    })
    
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
            -- If the class has the member and it's a function, it's a method.
            -- We must return the raw function so colon notation works: inst:method()
            local class_val = ModelClass[k]
            if class_val ~= nil then
                -- Important: if it's a proxy function from add_query_proxy, 
                -- we want the original function for instance calls.
                if type(class_val) == "function" then
                    return rawget(ModelClass, k) or Model[k] or class_val
                end
                return class_val 
            end
            
            local attr_val = t._attributes[k]
            if attr_val ~= nil then return attr_val end
            
            local rel_entry = ModelClass._relations and ModelClass._relations[k]
            if rel_entry and rel_entry.fn then
                if not t._relations_loaded[k] then
                    t._relations_loaded[k] = rel_entry.fn(t)
                end
                return t._relations_loaded[k]
            end
            return nil
        end,
        __newindex = function(t, k, v)
            if k:sub(1,1) == "_" or k == "errors" or k == "class" then rawset(t, k, v)
            else t._attributes[k] = v end
        end,
        __tostring = function(t)
            local attrs = t._attributes
            local display = attrs.name or attrs.title or attrs.username or attrs.id or "Model Instance"
            return tostring(display)
        end
    })
    return instance
end

-- ==========================
-- RELATIONSHIP HELPERS
-- ==========================

local function get_related_model(model_path, name)
    local RelatedModel = package.loaded[model_path] or package.loaded[name]
    if not RelatedModel then
        local ok, mod = pcall(require, model_path)
        if ok then RelatedModel = mod end
    end
    return RelatedModel
end

function Model:belongs_to(name, options)
    if not self or type(self) == "string" then return end -- Avoid dot-notation crash
    options = options or {}
    local model_path = options.model or ("app.models." .. name)
    self._relations = self._relations or {}
    local metadata = {
        type = "belongs_to",
        model_path = model_path,
        foreign_key = options.foreign_key,
        primary_key = options.primary_key,
        dependent = options.dependent
    }
    self._relations[name] = {
        fn = function(instance)
            local RelatedModel = get_related_model(model_path, name)
            if not RelatedModel then error("Could not load model: " .. model_path) end
            return instance:belongsTo(RelatedModel, metadata.foreign_key, metadata.primary_key, name)
        end,
        metadata = metadata
    }
end

function Model:has_many(name, options)
    if not self or type(self) == "string" then return end
    options = options or {}
    local singular_name = string_utils.singularize(name)
    local model_path = options.model or ("app.models." .. singular_name)
    self._relations = self._relations or {}
    local metadata = {
        type = "has_many",
        model_path = model_path,
        foreign_key = options.foreign_key,
        local_key = options.local_key,
        dependent = options.dependent,
        through = options.through,
        source = options.source or singular_name
    }
    local ModelClass = self
    self._relations[name] = {
        fn = function(instance)
            if metadata.through then
                local TargetModel = get_related_model(metadata.model_path, singular_name)
                local through_rel = ModelClass._relations[metadata.through]
                if not through_rel then error("Through association not found: " .. metadata.through) end
                local through_meta = through_rel.metadata
                local ThroughModel = get_related_model(through_meta.model_path, string_utils.singularize(metadata.through))
                local target_fk = metadata.source .. "_id"
                local parent_fk = through_meta.foreign_key or (string_utils.singularize(ModelClass.table_name or "") .. "_id")
                return TargetModel:query()
                    :select(TargetModel.table_name .. ".*")
                    :join(ThroughModel.table_name, ThroughModel.table_name .. "." .. target_fk, "=", TargetModel.table_name .. "." .. (TargetModel.primary_key or "id"))
                    :where(ThroughModel.table_name .. "." .. parent_fk, instance[ModelClass.primary_key or "id"])
            else
                local RelatedModel = get_related_model(model_path, singular_name)
                if not RelatedModel then error("Could not load model: " .. model_path) end
                return instance:hasMany(RelatedModel, metadata.foreign_key, metadata.local_key)
            end
        end,
        metadata = metadata
    }
end

function Model:has_one(name, options)
    if not self or type(self) == "string" then return end
    options = options or {}
    local model_path = options.model or ("app.models." .. name)
    self._relations = self._relations or {}
    local metadata = {
        type = "has_one",
        model_path = model_path,
        foreign_key = options.foreign_key,
        local_key = options.local_key,
        dependent = options.dependent
    }
    self._relations[name] = {
        fn = function(instance)
            local RelatedModel = get_related_model(model_path, name)
            if not RelatedModel then error("Could not load model: " .. model_path) end
            return instance:hasOne(RelatedModel, metadata.foreign_key, metadata.local_key)
        end,
        metadata = metadata
    }
    local build_name = "build_" .. name
    local create_name = "create_" .. name
    self[build_name] = function(instance, attrs)
        local RelatedModel = get_related_model(model_path, name)
        local fk = metadata.foreign_key or (string_utils.singularize(instance.table_name or "") .. "_id")
        attrs = attrs or {}
        attrs[fk] = instance[instance.primary_key or "id"]
        return RelatedModel:new(attrs)
    end
    self[create_name] = function(instance, attrs)
        local child = instance[build_name](instance, attrs)
        child:save()
        return child
    end
end

-- ==========================
-- QUERY METHODS
-- ==========================

function Model:query()
    local ModelClass = self.class or self
    local q = QueryBuilder.new(ModelClass):table(ModelClass.table_name or "")
    if ModelClass.soft_deletes then q:whereNull("deleted_at") end
    return q
end

function Model:find(id) return self:query():where(self.primary_key or "id", id):first() end
function Model:all() return self:query():get() end
function Model:first() return self:query():first() end
function Model:last() return self:query():orderBy(self.primary_key or "id", "DESC"):first() end
function Model:find_by(attributes)
    local q = self:query()
    for k, v in pairs(attributes) do q:where(k, v) end
    return q:first()
end

function Model:find_or_create_by(attributes)
    local record = self:find_by(attributes)
    if record then return record end
    return self:create(attributes)
end

function Model:first_or_create(attributes)
    return self:find_or_create_by(attributes)
end
function Model:exists(conditions)
    local q = self:query()
    if type(conditions) == "table" then for k, v in pairs(conditions) do q:where(k, v) end
    elseif conditions ~= nil then q:where(self.primary_key or "id", conditions) end
    return q:count() > 0
end

function Model:where(column, op, value) return self:query():where(column, op, value) end
function Model:limit(num) return self:query():limit(num) end
function Model:order(column, direction) return self:query():orderBy(column, direction) end

-- Aggregation proxies
function Model:count() return self:query():count() end
function Model:avg(column) return self:query():avg(column) end
function Model:sum(column) return self:query():sum(column) end
function Model:min(column) return self:query():min(column) end
function Model:max(column) return self:query():max(column) end

function Model:destroy_all()
    local items = self:all()
    local count = 0
    for _, item in ipairs(items) do if item:delete() then count = count + 1 end end
    return count
end

function Model:delete_all()
    return self:query():delete()
end

function Model:raw(sql, bindings) return QueryBuilder.raw(sql, bindings) end

function Model.transaction(callback)
    local DBManager = require("rio.database.manager")
    DBManager.begin()
    local ok, result = pcall(callback)
    if ok then DBManager.commit(); return result
    else DBManager.rollback(); error(result) end
end

-- ==========================
-- CRUD METHODS
-- ==========================

function Model:save()
    if not self:validate() then return false end
    return self._exists and self:_update() or self:_create()
end

function Model:create(attributes)
    local instance = self:new(attributes)
    local ok = instance:save()
    return ok and instance or nil, instance
end

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
    if self.soft_deletes then
        self.deleted_at = os.date("%Y-%m-%d %H:%M:%S")
        return self:query():where(self.primary_key or "id", id):update({deleted_at = self.deleted_at})
    end
    local ok = self:query():where(self.primary_key or "id", id):delete()
    if ok then self._exists = false; if self.after_delete then self.after_delete(self) end end
    return ok
end

function Model:_handleDependentAssociations()
    local ModelClass = self.class
    if not ModelClass._relations then return end
    for name, rel in pairs(ModelClass._relations) do
        local meta = rel.metadata
        if meta and meta.dependent then
            local association = self[name]
            if association then
                if meta.dependent == "destroy" then
                    if meta.type == "has_many" then
                        local children = association:get()
                        for _, child in ipairs(children) do child:delete() end
                    else association:delete() end
                elseif meta.dependent == "delete_all" then
                    if meta.type == "has_many" then association:delete()
                    else association:query():delete() end
                end
            end
        end
    end
end

function Model:_create()
    if self.before_create then self.before_create(self) end
    if self.before_save then self.before_save(self) end
    if self.timestamps ~= false then
        self.created_at = os.date("%Y-%m-%d %H:%M:%S")
        self.updated_at = os.date("%Y-%m-%d %H:%M:%S")
    end
    local data = self:_filterAttributes(self._attributes)
    local id = self:query():insert(data)
    if id then
        self[self.primary_key or "id"] = id
        self._exists = true; self._original = self:_copy(self._attributes)
        if self.after_create then self.after_create(self) end
        if self.after_save then self.after_save(self) end
        return true
    end
    return false
end

function Model:_update()
    if self.before_update then self.before_update(self) end
    if self.before_save then self.before_save(self) end
    if self.timestamps ~= false then self.updated_at = os.date("%Y-%m-%d %H:%M:%S") end
    local id = self[self.primary_key or "id"]
    local data = self:_filterAttributes(self._attributes)
    data[self.primary_key or "id"] = nil
    
    if self:query():where(self.primary_key or "id", id):update(data) then
        self._original = self:_copy(self._attributes)
        if self.after_update then self.after_update(self) end
        if self.after_save then self.after_save(self) end
        return true
    end
    return false
end

-- ==========================
-- RELATIONSHIPS (Instance)
-- ==========================

function Model:hasMany(RelatedModel, foreign_key, local_key)
    local lk = local_key or self.primary_key or "id"
    local fk = foreign_key or string_utils.singularize(self.class.table_name or "") .. "_id"
    local local_value = self[lk]
    local q = RelatedModel:query():where(fk, local_value)
    function q:build(attrs) attrs = attrs or {}; attrs[fk] = local_value; return RelatedModel:new(attrs) end
    function q:create(attrs) local child = self:build(attrs); child:save(); return child end
    return q
end

function Model:hasOne(RelatedModel, foreign_key, local_key)
    local lk = local_key or self.primary_key or "id"
    local fk = foreign_key or string_utils.singularize(self.class.table_name or "") .. "_id"
    return RelatedModel:query():where(fk, self[lk]):first()
end

function Model:belongsTo(RelatedModel, foreign_key, owner_key, relation_name)
    local fk = foreign_key or (relation_name and relation_name .. "_id") or (string_utils.singularize(RelatedModel.table_name or "") .. "_id")
    return RelatedModel:find(self[fk])
end

-- ==========================
-- HYDRATION
-- ==========================

function Model:_hydrate(data)
    local instance = self:new(data)
    instance._original = self:_copy(data)
    instance._exists = true
    return instance
end

function Model:_hydrateAll(results)
    local instances = {}
    for _, row in ipairs(results or {}) do table.insert(instances, self:_hydrate(row)) end
    return instances
end

-- ==========================
-- VALIDATIONS & SERIALIZATION
-- ==========================

function Model:validate()
    self.errors:clear()
    if not self.validates then return true end
    for field, rules in pairs(self.validates) do
        local value = self[field]
        if type(rules) == "string" then rules = { [rules] = true } end
        if rules.presence and (value == nil or value == "" or (type(value) == "string" and value:match("^%s*$"))) then
            local msg = (type(rules.presence) == "table" and rules.presence.message) or "can't be blank"
            self.errors:add(field, msg)
        end
        if rules.uniqueness and value then
            local q = self:query():where(field, value)
            if self._exists then q:where(self.primary_key or "id", "!=", self[self.primary_key or "id"]) end
            local found = q:first()
            if found then
                local msg = (type(rules.uniqueness) == "table" and rules.uniqueness.message) or "has already been taken"
                self.errors:add(field, msg)
            end
        end
        if rules.length and value then
            local len = #tostring(value); local r = rules.length
            if r.minimum and len < r.minimum then self.errors:add(field, r.message or "is too short") end
            if r.maximum and len > r.maximum then self.errors:add(field, r.message or "is too long") end
        end
        if rules.format and value then
            local r = rules.format
            if r.with and not tostring(value):match(r.with) then
                self.errors:add(field, r.message or "is invalid")
            end
        end
        if rules.numericality and value then
            local r = rules.numericality
            local num = tonumber(value)
            if not num then
                self.errors:add(field, r.message or "is not a number")
            else
                if r.only_integer and math.floor(num) ~= num then
                    self.errors:add(field, r.message or "must be an integer")
                end
                if r.greater_than and num <= r.greater_than then
                    self.errors:add(field, r.message or "must be greater than " .. r.greater_than)
                end
                if r.less_than and num >= r.less_than then
                    self.errors:add(field, r.message or "must be less than " .. r.less_than)
                end
            end
        end
    end
    return not self.errors:any()
end

function Model:_filterAttributes(data)
    local filtered = {}
    local class = self.class or self
    local fillable = class.fillable
    
    if type(fillable) == "table" and #fillable > 0 then
        local allowed = {}
        for _, f in ipairs(fillable) do allowed[f] = true end
        for k, v in pairs(data) do
            if allowed[k] then filtered[k] = v end
        end
        if class.timestamps ~= false then
            if data.created_at then filtered.created_at = data.created_at end
            if data.updated_at then filtered.updated_at = data.updated_at end
        end
        return filtered
    end

    for k, v in pairs(data) do 
        if type(k) == "string" and k:sub(1,1) ~= "_" and k ~= "errors" and k ~= "class" then 
            filtered[k] = v 
        end 
    end
    return filtered
end

function Model:_copy(t) local c = {}; for k,v in pairs(t) do c[k]=v end; return c end

function Model:toTable()
    local data = {}
    local whitelist = self.attributes
    local hidden = self.hidden
    if whitelist and #whitelist > 0 then
        for _, field in ipairs(whitelist) do
            if type(self[field]) == "function" then data[field] = self[field](self)
            else data[field] = self._attributes[field] end
        end
        return data
    end
    for k, v in pairs(self._attributes) do
        local hide = false
        for _, h in ipairs(hidden) do if k == h then hide = true; break end end
        if not hide then data[k] = v end
    end
    return data
end

function Model:toJSON() return self:toTable() end
function Model:toArray() return self:toTable() end

return Model
