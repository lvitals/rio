-- rio/lib/rio/middleware/logger.lua
-- Middleware for logging requests.

local M = {}

M.description = "Logs incoming requests and outgoing responses."

-- Formats timestamp
local function format_time()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local colors = {
    reset = "\27[0m",
    green = "\27[32m",
    yellow = "\27[33m",
    red = "\27[31m",
    cyan = "\27[36m"
}

local function colorize_status(status)
    local s = tonumber(status)
    if not s then return status end
    
    if s >= 200 and s < 300 then return colors.green .. status .. colors.reset
    elseif s >= 300 and s < 400 then return colors.cyan .. status .. colors.reset
    elseif s >= 400 and s < 500 then return colors.yellow .. status .. colors.reset
    elseif s >= 500 then return colors.red .. status .. colors.reset
    end
    return status
end

-- Basic logger (stdout)
function M.basic()
    return function(ctx, next)
        local start_time = os.clock()
        
        -- Let the request proceed
        local ok, result = pcall(next)
        
        -- Log the response
        local duration = (os.clock() - start_time) * 1000
        local status = ctx.response_headers:get(":status") or "200"
        
        print(string.format('[%s] "%s %s" %s - %.2fms', 
              format_time(), 
              ctx.method, 
              ctx.path, 
              colorize_status(status), 
              duration))
        
        if not ok then
            -- Print the error to console
            print(string.format("%s-- RIO ERROR --%s", colors.red, colors.reset))
            print(tostring(result))
            print(string.rep("-", 40))
            error(result) -- Re-raise if next() failed
        end
        return result
    end
end

-- Detailed logger
function M.detailed()
    return function(ctx, next)
        local start_time = os.clock()
        
        -- Log detailed request info
        print(string.format("\n-- Rio Request -- [%s]", format_time()))
        print(string.format("-> %s %s", ctx.method, ctx.path))
        if ctx.route then
            print(string.format("   Route: %s", ctx.route))
        end
        
        -- Execute the rest of the chain
        local result = next()
        
        -- Log detailed response info
        local duration = (os.clock() - start_time) * 1000
        local status = ctx.response_headers:get(":status") or "200"
        
        print(string.format("<- %s (%.2fms)", status, duration))
        
        return result
    end
end

-- Custom formatter logger
function M.custom(formatter)
    if type(formatter) ~= "function" then
        error("formatter must be a function")
    end
    
    return function(ctx, next)
        local start_time = os.clock()
        
        local result = next()
        
        local duration = (os.clock() - start_time) * 1000
        local status = ctx.response_headers:get(":status") or 0
        
        local log_data = {
            timestamp = format_time(),
            method = ctx.method,
            path = ctx.path,
            route = ctx.route,
            status = tonumber(status) or 0,
            duration = duration,
            query = ctx.query,
            params = ctx.params
        }
        
        local message = formatter(log_data, ctx)
        if message then
            print(message)
        end
        
        return result
    end
end

return M
