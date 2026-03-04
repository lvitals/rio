-- config/application.lua
local env = os.getenv("RIO_ENV") or "development"

return {
    server = {
        port = 8080,
        host = "0.0.0.0"
    },
    environment = env,
    api_only = true,
    title = "Rio Showcase API",
    api_version = "v1",
    
    -- Cache Configuration
    query_cache = true, -- Level 1: Request-level SQL cache
    perform_caching = true, -- Level 2: Enable Application cache
    cache_store = "file", -- Persist cache in tmp/cache/
    
    version = "1.0.0",
    api_format = "json"
}
