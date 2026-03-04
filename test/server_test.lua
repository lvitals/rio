local Server = require("rio.server")

describe("Rio Server", function()
    local app

    before_each(function()
        app = Server.new({ perform_caching = false })
    end)

    it("should register middlewares", function()
        local mw = function(ctx, next_mw) return next_mw() end
        app:use(mw)
        assert.equals(1, #app.middlewares)
        assert.equals(mw, app.middlewares[1].handler)
    end)

    it("should map routes correctly", function()
        local handler = function(ctx) return ctx:text("Hello") end
        app:get("/hello", handler)
        
        local found_handler, params = app.router:match("GET", "/hello")
        assert.equals(handler, found_handler)
    end)

    it("should handle route groups", function()
        app:group("/api", function(api)
            api:get("/test", function() end)
        end)
        
        local found_handler = app.router:match("GET", "/api/test")
        assert.is_not_nil(found_handler)
        
        local not_found = app.router:match("GET", "/test")
        assert.is_nil(not_found)
    end)
    
    it("should process requests successfully", function()
        app:get("/ping", function(ctx) return ctx:text("pong", 200) end)
        
        local mock_adapter = {
            method = "GET",
            path = "/ping",
            query = {},
            headers = {},
            get_body = function() return nil end,
            write_headers = function(self, h) self.status = h:get(":status"); return true end,
            write_body = function(self, b) self.body = b; return true end,
            close = function() end
        }
        
        app:_process_request(mock_adapter)
        assert.equals("200", mock_adapter.status)
        assert.equals("pong", mock_adapter.body)
    end)
end)
