-- tests/middleware/logger_test.lua
local logger = require("rio.middleware.logger")

describe("Logger Middleware", function()
    local function mock_context()
        return {
            method = "GET",
            path = "/test",
            response_headers = {
                get = function(self, k) return 200 end
            }
        }
    end

    it("should provide a basic logger handler", function()
        local handler = logger.basic()
        assert.is_function(handler)
    end)

    it("should call next() without crashing", function()
        local ctx = mock_context()
        local handler = logger.basic()
        local next_called = false
        
        -- Wrap print to avoid polluting test output
        local old_print = _G.print
        _G.print = function() end
        
        handler(ctx, function() 
            next_called = true
            return "ok"
        end)
        
        _G.print = old_print
        assert.is_true(next_called)
    end)
end)
