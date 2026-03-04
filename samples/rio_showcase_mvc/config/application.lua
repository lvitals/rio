-- config/application.lua
-- Application-wide configurations for the Rio framework.

return {
    server = {
        port = 8080,
        host = "0.0.0.0"
    },
    environment = "development",
    api_only = false,
    title = "Samples/rioShowcaseMvc API",
    description = "Auto-generated documentation for Samples/rioShowcaseMvc",
    version = "1.0.0",
    api_format = "json", -- Options: "json", "jsonapi"

    -- Cache Configuration
    query_cache = true,      -- Level 1: Automatic SQL result caching (request-level)
    perform_caching = true,  -- Level 2: Manual Application caching (persistent)
    cache_store = "file",    -- Level 2 adapter: "file" or "memory"
    cache_dir = "tmp/cache", -- Directory for file-based cache

    -- Documentation settings
    -- openapi_path = "/docs",           -- Changes the UI path from /docs to your preference
    -- openapi_json_path = "/openapi.json" -- Changes the JSON spec path
}
