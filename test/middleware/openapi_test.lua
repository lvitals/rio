local openapi = require("rio.middleware.openapi")
local rio = require("rio")

describe("Rio OpenAPI Middleware", function()
    local app

    before_each(function()
        app = rio.new({
            app_name = "TestApp",
            security = {
                headers = {
                    ["X-Global-Header"] = "global-val"
                }
            }
        })

        -- Mock a controller with OpenAPI metadata
        local MockController = {
            openapi = {
                index = {
                    summary = "Custom Summary",
                    headers = {
                        ["X-Route-Header"] = "route-val"
                    }
                }
            },
            index = function(ctx) return ctx:text("ok") end
        }

        -- Register route and metadata manually for testing
        local handler = MockController.index
        app:get("/test-route", handler)
        app.routes_meta[handler] = { 
            controller = "mock", 
            action = "index" 
        }
        
        -- Mock the require for the controller reflection
        package.loaded["app.controllers.mock_controller"] = MockController
    end)

    it("should include global headers in OpenAPI spec", function()
        local mw = openapi.create(app)
        local ctx = {
            path = "/openapi.json",
            query = {},
            json = function(self, spec)
                local path_item = spec.paths["/test-route"].get
                local found_global = false
                
                for _, param in ipairs(path_item.parameters) do
                    if param.name == "X-Global-Header" then
                        found_global = true
                        assert.equals("header", param["in"])
                    end
                end
                
                assert.is_true(found_global, "Global header not found in spec")
                return true
            end
        }

        mw(ctx, function() end)
    end)

    it("should include route-specific headers in OpenAPI spec", function()
        local mw = openapi.create(app)
        local ctx = {
            path = "/openapi.json",
            query = {},
            json = function(self, spec)
                local path_item = spec.paths["/test-route"].get
                local found_route_header = false
                
                for _, param in ipairs(path_item.parameters) do
                    if param.name == "X-Route-Header" then
                        found_route_header = true
                        assert.equals("header", param["in"])
                    end
                end
                
                assert.is_true(found_route_header, "Route-specific header not found in spec")
                return true
            end
        }

        mw(ctx, function() end)
    end)

    it("should serve the Swagger UI HTML with correct CSP", function()
        local mw = openapi.create(app)
        local csp_set = nil
        local ctx = {
            path = "/docs",
            setHeader = function(self, k, v)
                if k == "Content-Security-Policy" then csp_set = v end
            end,
            html = function(self, html)
                assert.truthy(html:find("SwaggerUIBundle"))
                return true
            end
        }

        mw(ctx, function() end)
        assert.truthy(csp_set:find("unpkg.com"), "CSP should allow unpkg.com for Swagger UI")
    end)
end)
