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
