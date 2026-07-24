-- rio/lib/rio/cli/ports.lua

local M = {}

local socket_ok, socket = pcall(require, "socket")

function M.is_free(port, host)
    if not socket_ok then return true end

    host = host or "0.0.0.0"
    local test_socket = socket.tcp()
    test_socket:settimeout(0.2)

    local test_host = (host == "0.0.0.0") and "127.0.0.1" or host
    local conn_ok = test_socket:connect(test_host, port)
    test_socket:close()

    return not conn_ok
end

return M
