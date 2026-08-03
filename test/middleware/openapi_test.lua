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

    it("should filter OpenAPI paths by API version", function()
        app = rio.new({
            app_name = "VersionedApp",
            api_versions = { "v1", "v2" }
        })

        app:api("v1", function(v1)
            v1:get("/users", function() end)
        end)

        app:api("v2", function(v2)
            v2:get("/users", function() end)
        end)

        app:get("/health", function() end)

        local mw = openapi.create(app)
        local ctx = {
            path = "/openapi.json",
            query = { v = "v1" },
            json = function(self, spec)
                assert.is_not_nil(spec.paths["/api/v1/users"])
                assert.is_nil(spec.paths["/api/v2/users"])
                assert.is_not_nil(spec.paths["/health"])
                assert.equals("v1", spec.info.version)
                return true
            end
        }

        mw(ctx, function() end)
    end)

    it("should infer versions from legacy /api/vN route groups", function()
        app = rio.new({
            app_name = "LegacyVersionedApp",
            api_versions = { "v1", "v2" }
        })

        app:group("/api/v1", function(v1)
            v1:get("/me", function() end)
        end)

        app:group("/api/v2", function(v2)
            v2:get("/me", function() end)
        end)

        local mw = openapi.create(app)
        local ctx = {
            path = "/openapi.json",
            query = { v = "v2" },
            json = function(self, spec)
                assert.is_nil(spec.paths["/api/v1/me"])
                assert.is_not_nil(spec.paths["/api/v2/me"])
                return true
            end
        }

        mw(ctx, function() end)
    end)

    it("should serve OpenAPI JSON from a versioned API path", function()
        app = rio.new({
            app_name = "VersionedJsonApp",
            api_versions = { "v1", "v2" }
        })

        app:api("v1", function(v1)
            v1:get("/status", function() end)
        end)

        app:api("v2", function(v2)
            v2:get("/status", function() end)
        end)

        local mw = openapi.create(app)
        local ctx = {
            path = "/api/v2/openapi.json",
            query = {},
            json = function(self, spec)
                assert.equals("v2", spec.info.version)
                assert.is_nil(spec.paths["/api/v1/status"])
                assert.is_not_nil(spec.paths["/api/v2/status"])
                return true
            end
        }

        mw(ctx, function() end)
    end)

    it("should configure Swagger UI with version URLs and a default version", function()
        app = rio.new({
            app_name = "VersionedDocsApp",
            api_versions = { "v1", "v2" }
        })

        local mw = openapi.create(app)
        local ctx = {
            path = "/docs",
            setHeader = function() end,
            html = function(self, html)
                assert.truthy(html:find('"urls.primaryName":', 1, true))
                assert.truthy(html:find('/openapi.json?v=v1', 1, true))
                assert.truthy(html:find('/openapi.json?v=v2', 1, true))
                return true
            end
        }

        mw(ctx, function() end)
    end)
end)
