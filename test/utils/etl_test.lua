-- test/utils/etl_test.lua
local etl = require("rio.utils.etl")

describe("Rio ETL Template Engine", function()
    it("should render basic variables", function()
        local result = etl.render("Hello <%= name %>", { name = "Leandro" })
        assert.equals("Hello Leandro", result)
    end)

    it("should escape HTML by default", function()
        local result = etl.render("<b><%= code %></b>", { code = "<script>" })
        assert.equals("<b>&lt;script&gt;</b>", result)
    end)

    it("should NOT escape HTML with <%-", function()
        local result = etl.render("<b><%- code %></b>", { code = "<script>" })
        assert.equals("<b><script></b>", result)
    end)

    it("should support Lua blocks", function()
        local template = [[
<ul>
<% for i=1,3 do %>
  <li>Item <%= i %></li>
<% end %>
</ul>]]
        local result = etl.render(template)
        assert.truthy(result:find("<li>Item 1</li>"))
        assert.truthy(result:find("<li>Item 2</li>"))
        assert.truthy(result:find("<li>Item 3</li>"))
    end)

    it("should handle nil values as empty strings in output", function()
        local result = etl.render("Value: '<%= val %>'", { val = nil })
        assert.equals("Value: ''", result)
    end)
end)
