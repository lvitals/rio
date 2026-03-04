local response = require("rio.core.response")

describe("Rio Response Core", function()
    local mock_adapter

    before_each(function()
        mock_adapter = {
            headers_written = false,
            body_written = false,
            closed = false,
            write_headers = function(self, h, end_stream)
                self.headers_written = true
                self.saved_headers = h
                return true, nil
            end,
            write_body = function(self, b)
                self.body_written = true
                self.saved_body = b
                return true, nil
            end,
            close = function(self)
                self.closed = true
            end
        }
    end)

    it("should send plain text responses", function()
        response.text(mock_adapter, 200, "Hello World")
        assert.is_true(mock_adapter.headers_written)
        assert.is_true(mock_adapter.body_written)
        assert.is_true(mock_adapter.closed)
        assert.equals("Hello World", mock_adapter.saved_body)
        assert.equals("200", mock_adapter.saved_headers:get(":status"))
        assert.equals("text/plain; charset=utf-8", mock_adapter.saved_headers:get("content-type"))
    end)

    it("should send json responses and serialize tables", function()
        response.json(mock_adapter, 201, { success = true })
        assert.is_true(mock_adapter.headers_written)
        assert.is_true(mock_adapter.body_written)
        assert.truthy(mock_adapter.saved_body:find('"success":true'))
        assert.equals("201", mock_adapter.saved_headers:get(":status"))
        assert.equals("application/json; charset=utf-8", mock_adapter.saved_headers:get("content-type"))
    end)

    it("should send html responses", function()
        response.html(mock_adapter, 404, "<h1>Not Found</h1>")
        assert.is_true(mock_adapter.headers_written)
        assert.is_true(mock_adapter.body_written)
        assert.equals("<h1>Not Found</h1>", mock_adapter.saved_body)
        assert.equals("404", mock_adapter.saved_headers:get(":status"))
        assert.equals("text/html; charset=utf-8", mock_adapter.saved_headers:get("content-type"))
    end)

    it("should send redirect responses without body", function()
        local headers_utils = require("rio.utils.compat")
        local custom_headers = headers_utils.new_headers()
        custom_headers:upsert("Location", "/new-url")
        
        response.redirect(mock_adapter, 302, custom_headers)
        
        assert.is_true(mock_adapter.headers_written)
        assert.is_false(mock_adapter.body_written) -- redirect has no body
        assert.equals("302", mock_adapter.saved_headers:get(":status"))
        assert.equals("/new-url", mock_adapter.saved_headers:get("Location"))
    end)
end)
