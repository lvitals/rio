-- rio/lib/rio/middleware/query_cache.lua
-- Clears the ActiveRecord-style Query Cache on each request

local DBManager = require("rio.database.manager")

return function(ctx, next_fn)
    -- Limpa o cache de queries do banco de dados para este request
    DBManager.clear_query_cache()
    
    return next_fn()
end
