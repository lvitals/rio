-- rio/lib/rio/cli/generators/fields.lua
-- Field parser used by resource generators.

local M = {}

function M.parse(fields)
    local definitions = {}
    local order = {}

    for _, field in ipairs(fields or {}) do
        local name, type_info = field:match("([^:]+):(.+)")
        if name and type_info then
            if not definitions[name] then
                table.insert(order, name)
                definitions[name] = { options = {} }
            end

            local col = definitions[name]
            local base_type = type_info:match("^([%a_]+)")
            local options_str = type_info:match("{([^}]+)}") or type_info:match("^[%a_]+(.*)$")

            if not col.type then col.type = base_type end

            if options_str and options_str ~= "" then
                local precision = options_str:match("^(%d+),?%d*$")
                if precision then
                    if col.type == "string" or col.type == "email" or col.type == "password" then
                        col.options.limit = tonumber(precision)
                    elseif col.type == "decimal" then
                        if not col.options.precision then
                            col.options.precision = tonumber(precision)
                        else
                            col.options.scale = tonumber(precision)
                        end
                    end
                end

                local default_value = options_str:match("default=([^,%s}]+)")
                if default_value then
                    if default_value == "true" then
                        col.options.default = true
                    elseif default_value == "false" then
                        col.options.default = false
                    elseif tonumber(default_value) then
                        col.options.default = tonumber(default_value)
                    else
                        col.options.default = default_value:gsub("^['\"]", ""):gsub("['\"]$", "")
                    end
                end

                if options_str:find("unique=true") then col.options.unique = true end
                if options_str:find("polymorphic=true") then col.options.polymorphic = true end
                if options_str:find("has_one=true") then col.options.has_one = true end
            end
        end
    end

    return order, definitions
end

return M
