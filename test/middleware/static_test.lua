local static_mw = require("rio.middleware.static")

describe("Rio Static Middleware", function()
    local function mock_ctx(path)
        return {
            path = path or "/",
            method = "GET",
            error = function(self, status, msg) return { status = status, msg = msg } end,
            getHeader = function() return nil end,
            setHeader = function() end,
            html = function(self, content, status) return { status = status, content = content } end,
            text = function(self, content, status) return { status = status, content = content } end
        }
    end

    it("should reject unsafe paths (traversal)", function()
        local mw = static_mw.create(nil, { root = "public" })
        local ctx = mock_ctx("/../../etc/passwd")
        
        local res = mw(ctx, function() return "next" end)
        assert.is_table(res)
        assert.equals(403, res.status)
    end)

    it("should call next() if file does not exist", function()
        local mw = static_mw.create(nil, { root = "non_existent_folder_123" })
        local ctx = mock_ctx("/some_file.txt")
        
        local res = mw(ctx, function() return "next_called" end)
        assert.equals("next_called", res)
    end)
end)
