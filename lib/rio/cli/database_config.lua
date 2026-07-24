-- rio/lib/rio/cli/database_config.lua
-- Templates for generated config/database.lua files.

local M = {}

function M.generate(database_adapter, project_name, config)
    config = config or {}
    local database_content = ""

    if database_adapter == "sqlite" or database_adapter == "sqlite3" then
        database_content = [[
-- config/database.lua
-- Database configurations for the Rio framework.
return {
    development = {
        adapter = "sqlite",
        database = "db/development.sqlite3"
    },
    test = {
        adapter = "sqlite",
        database = "db/test.sqlite3"
    },
    production = {
        adapter = "sqlite",
        database = "db/production.sqlite3"
    }
}
]]
    elseif database_adapter == "postgresql" or database_adapter == "postgres" then
        database_content = string.format([[
-- config/database.lua
-- Database configurations for the Rio framework.
return {
    development = {
        adapter = "postgres",
        host = "%s",
        port = %s,
        username = "%s",
        password = "%s",
        database = "%s",
        -- charset = "UTF8",
    },
    test = {
        adapter = "postgres",
        host = "%s",
        port = %s,
        username = "%s",
        password = "%s",
        database = "%s_test",
        -- charset = "UTF8",
    },
    production = {
        adapter = "postgres",
        host = "%s",
        port = %s,
        username = "%s",
        password = "%s",
        database = "%s_production",
        -- charset = "UTF8",
    }
}
]],
            config.host or "localhost", config.port or 5432, config.username or "rio_dev", config.password or "password", config.database or (project_name .. "_development"),
            config.host or "localhost", config.port or 5432, config.username or "rio_dev", config.password or "password", project_name,
            config.host or "localhost", config.port or 5432, config.username or "rio_dev", config.password or "password", project_name)
    elseif database_adapter == "mysql" then
        database_content = string.format([[
-- config/database.lua
-- Database configurations for the Rio framework.
return {
    development = {
        adapter = "mysql",
        host = "%s",
        port = %s,
        username = "%s",
        password = "%s",
        database = "%s",
        -- engine = "InnoDB",
        -- charset = "utf8mb4",
    },
    test = {
        adapter = "mysql",
        host = "%s",
        port = %s,
        username = "%s",
        password = "%s",
        database = "%s_test",
        -- engine = "InnoDB",
        -- charset = "utf8mb4",
    },
    production = {
        adapter = "mysql",
        host = "%s",
        port = %s,
        username = "%s",
        password = "%s",
        database = "%s_production",
        -- engine = "InnoDB",
        -- charset = "utf8mb4",
    }
}
]],
            config.host or "127.0.0.1", config.port or 3306, config.username or "root", config.password or "password", config.database or (project_name .. "_development"),
            config.host or "127.0.0.1", config.port or 3306, config.username or "root", config.password or "password", project_name,
            config.host or "127.0.0.1", config.port or 3306, config.username or "root", config.password or "password", project_name)
    end

    return database_content
end

return M
