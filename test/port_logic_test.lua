-- local Server = require("rio.server")
-- local compat = require("rio.utils.compat")

-- describe("Rio Server Port Logic", function()
--     local app
--     local original_listen = compat.http_server.listen
--     local captured_options

--     before_each(function()
--         app = Server.new({ 
--             perform_caching = false,
--             server = { port = 8080, host = "0.0.0.0" }
--         })
--         -- Mock listen to capture options instead of starting a server
--         compat.http_server.listen = function(options)
--             captured_options = options
--             return { loop = function() end } -- Mock instance
--         end
--         os.execute("unset RIO_PORT")
--         os.execute("unset RIO_BINDING")
--     end)

--     after_each(function()
--         compat.http_server.listen = original_listen
--         os.execute("unset RIO_PORT")
--         os.execute("unset RIO_BINDING")
--     end)

--     it("should use port from RIO_PORT environment variable", function()
--         -- Note: os.setenv is not standard in Lua 5.1, we might need to use a workaround
--         -- if the environment is not picking up os.execute("export ...")
--         -- However, Server:listen uses os.getenv, so we can mock os.getenv
--         local old_getenv = os.getenv
--         os.getenv = function(name)
--             if name == "RIO_PORT" then return "9999" end
--             return old_getenv(name)
--         end

--         app:listen()
        
--         assert.equals(9999, captured_options.port)
        
--         os.getenv = old_getenv
--     end)

--     it("should prioritize RIO_PORT over config", function()
--         local old_getenv = os.getenv
--         os.getenv = function(name)
--             if name == "RIO_PORT" then return "7777" end
--             return old_getenv(name)
--         end

--         -- Config has 8080 (set in before_each)
--         app:listen()
        
--         assert.equals(7777, captured_options.port)
        
--         os.getenv = old_getenv
--     end)

--     it("should use config if RIO_PORT is not set", function()
--         app.config.server.port = 6666
--         app:listen()
        
--         assert.equals(6666, captured_options.port)
--     end)

--     it("should use default 8080 if nothing is set", function()
--         app.config.server = nil
--         app:listen()
        
--         assert.equals(8080, captured_options.port)
--     end)
-- end)
