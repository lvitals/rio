local etl = require("rio.utils.etl")

describe("ETL Template Engine", function()
  it("should render simple text", function()
    local template = "Hello World"
    local result = etl.render(template)
    assert.equals("Hello World", result)
  end)

  it("should render with variables", function()
    local template = "Hello <%= name %>!"
    local result = etl.render(template, { name = "Rio" })
    assert.equals("Hello Rio!", result)
  end)

  it("should execute lua code", function()
    local template = "<% local x = 10 %><%= x + 5 %>"
    local result = etl.render(template)
    assert.equals("15", result)
  end)

  it("should handle loops", function()
    local template = "<% for i=1,3 do %><%= i %><% end %>"
    local result = etl.render(template)
    assert.equals("123", result)
  end)

  it("should escape HTML by default", function()
    local template = "<%= tag %>"
    local result = etl.render(template, { tag = "<script>alert(1)</script>" })
    assert.equals("&lt;script&gt;alert(1)&lt;/script&gt;", result)
  end)

  it("should NOT escape HTML with <%-", function()
    local template = "<%- tag %>"
    local result = etl.render(template, { tag = "<b>Bold</b>" })
    assert.equals("<b>Bold</b>", result)
  end)

  it("should handle nil values as empty strings in <%= %>", function()
    local template = "[<%= nothing %>]"
    local result = etl.render(template, { nothing = nil })
    assert.equals("[]", result)
  end)
  
  it("should handle nested tables and complex expressions", function()
    local template = "<%= user.name %> is <%= user.age %> years old."
    local result = etl.render(template, { user = { name = "Alice", age = 30 } })
    assert.equals("Alice is 30 years old.", result)
  end)
end)
