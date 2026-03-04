-- config/application.lua
-- Application-wide configurations for the Rio framework.

return {
    server = {
        port = 8080,
        host = "0.0.0.0"
    },
    environment = "development",
    api_only = false,
    title = "TestProject API",
    description = "Auto-generated documentation for TestProject",
    version = "1.0.0",
    api_format = "json", -- Options: "json", "jsonapi"

    -- Documentation settings
    -- openapi_path = "/docs",           -- Changes the UI path from /docs to your preference
    -- openapi_json_path = "/openapi.json" -- Changes the JSON spec path
}
