if not describe then
    print("Usage: busted test/cli/shell_test.lua")
    os.exit(1)
end

package.path = "./?.lua;./?/init.lua;lib/?.lua;lib/?/init.lua;" .. package.path

local shell = require("rio.cli.shell")
local test_command = require("rio.cli.commands.test_command")
local test_cli_command = require("rio.cli.commands.test")

describe("Rio CLI shell command helpers", function()
    local function fake_capture(output, close_ok)
        return function()
            return {
                read = function() return output end,
                close = function() return close_ok ~= false end
            }
        end
    end

    local function contains(value, fragment)
        assert.truthy(value:find(fragment, 1, true))
    end

    it("quotes shell arguments without allowing argument splitting", function()
        assert.equals("''", shell.quote(""))
        assert.equals("'hello world'", shell.quote("hello world"))
        assert.equals([['a'"'"'b']], shell.quote("a'b"))
        assert.equals("'$HOME'", shell.quote("$HOME"))
        assert.equals("'a; rm -rf x'", shell.quote("a; rm -rf x"))
        assert.equals("'a && b | c * ?'", shell.quote("a && b | c * ?"))
    end)

    it("uses the fully expanded LuaRocks PATH when it is available", function()
        local fallback_path = "/usr/bin:/bin"
        local luarocks_bin = "/home/user/.luarocks/bin"
        local detected_path = luarocks_bin .. ":" .. fallback_path

        assert.equals(
            detected_path,
            test_command.detect_executable_path(fallback_path, fake_capture(detected_path .. "\n"))
        )
    end)

    it("keeps the original PATH when LuaRocks does not provide one", function()
        local fallback_path = "/usr/bin:/bin"

        assert.equals(
            fallback_path,
            test_command.detect_executable_path(fallback_path, fake_capture(""))
        )
    end)

    it("keeps the original PATH when LuaRocks path detection fails", function()
        local fallback_path = "/usr/bin:/bin"
        local partial_path = "/home/user/.luarocks/bin"

        assert.equals(
            fallback_path,
            test_command.detect_executable_path(fallback_path, fake_capture(partial_path, false))
        )
    end)

    it("builds rio test command from structured arguments", function()
        local framework_lua_path = "/rio/lib/?.lua"
        local executable_path = "/home/user/.luarocks/bin:/usr/bin:/bin"
        local test_target = "test/my suite/"
        local filter_arg = "creates user's account"

        local command = test_command.build({
            framework_lua_path = framework_lua_path,
            effective_lua_path = "/rocks/share/?.lua",
            original_lua_path = "/system/share/?.lua",
            effective_lua_cpath = "/rocks/lib/?.so",
            original_lua_cpath = "/system/lib/?.so",
            executable_path = executable_path,
            lua_bin = "lua5.4",
            test_args = { test_target, "--filter", filter_arg }
        })

        contains(command, shell.export("PATH", executable_path))
        contains(command, framework_lua_path)
        contains(command, shell.quote(test_target))
        contains(command, shell.quote(filter_arg))
    end)

    it("normalizes signal exits using POSIX exit code convention", function()
        assert.equals(130, shell.status_code(nil, "signal", 2))
    end)

    it("normalizes encoded numeric os.execute statuses", function()
        assert.equals(23, shell.status_code(23 * 256))
    end)

    it("returns busted failures without terminating the process", function()
        local original_execute = shell.execute
        local original_detect_executable_path = test_command.detect_executable_path
        local captured_command

        local ok, err = xpcall(function()
            shell.execute = function(command)
                captured_command = command
                return false, 23
            end
            test_command.detect_executable_path = function(fallback_path)
                return fallback_path
            end

            local success, exit_code = test_cli_command.run({
                ui = { header = function() end },
                framework_lib_path = "/rio/lib/?.lua",
                get_lua_paths = function()
                    return "/rocks/share/?.lua", "/rocks/lib/?.so"
                end
            }, { "test/failing_test.lua" })

            assert.is_false(success)
            assert.equals(23, exit_code)
            contains(captured_command, shell.quote("test/failing_test.lua"))
        end, debug.traceback)

        shell.execute = original_execute
        test_command.detect_executable_path = original_detect_executable_path

        if not ok then
            error(err, 0)
        end
    end)
end)
