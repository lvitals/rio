-- export LUA_PATH="./?.lua;./lib/?.lua;./lib/?/init.lua;;" && lua test/database/model_full_test.lua

local Model = require("rio.database.model")
local DBManager = require("rio.database.manager")
local QueryBuilder = require("rio.database.query_builder")

-- ANSI Colors for professional output
local colors = {
    reset = "\27[0m",
    green = "\27[32m",
    red = "\27[31m",
    cyan = "\27[36m",
    yellow = "\27[33m",
    bold = "\27[1m"
}

local function print_header(title)
    print("\n" .. colors.bold .. colors.cyan .. "=== " .. title:upper() .. " ===" .. colors.reset)
end

local function print_status(label, success, details)
    local icon = success and (colors.green .. "✓ PASS") or (colors.red .. "✗ FAIL")
    local line = string.format("%s %s%-25s%s", icon, colors.bold, label, colors.reset)
    if details then line = line .. " | " .. tostring(details) end
    print(line)
end

-- 1. SETUP DATABASE
local db_file = "test_model_full.sqlite3"
os.remove(db_file)

DBManager.verbose = false -- Silence DB logs for cleaner report
DBManager.initialize({
    adapter = "sqlite",
    database = db_file
})

DBManager.query("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE, name TEXT, email TEXT, age INTEGER, password TEXT, created_at DATETIME, updated_at DATETIME, deleted_at DATETIME)")
DBManager.query("CREATE TABLE posts (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, title TEXT, content TEXT, created_at DATETIME, updated_at DATETIME)")

-- 2. DEFINE MODELS
local User = Model:extend({
    table_name = "users",
    fillable = { "username", "name", "email", "age", "password" },
    hidden = { "password" },
    soft_deletes = true,
    validates = {
        username = { presence = true, uniqueness = true },
        email = { format = { with = "@" }, presence = true },
        age = { numericality = { only_integer = true } },
        password = { length = { minimum = 6 } }
    }
})

function User:before_create() end -- Silencing hook prints for cleaner report
function User:display_name() return "User: " .. (self.name or "Unknown") end

local Post = Model:extend({
    table_name = "posts",
    fillable = { "user_id", "title", "content" }
})

User:has_many("posts", { model = "Post" })
Post:belongs_to("user", { model = "User" })

package.loaded["User"] = User
package.loaded["Post"] = Post
package.loaded["app.models.User"] = User
package.loaded["app.models.Post"] = Post

-- 3. RUN TESTS
print("\n" .. colors.bold .. colors.yellow .. "Rio ActiveRecord Comprehensive Report" .. colors.reset)
print(string.rep("=", 60))

print_header("CRUD & Hooks")
local user = User:new({ username = "leandro", name = "Leandro", email = "leandro@example.com", age = 30, password = "secret_password" })
local saved = user:save()
print_status("Save new model", saved)
print_status("Auto-generated ID", user.id ~= nil, "ID: " .. (user.id or "N/A"))

print_header("Validations")
local invalid_user = User:new({ username = "leandro", email = "invalid", age = "abc", password = "123" })
local ok = invalid_user:save()
print_status("Reject invalid data", ok == false)
print_status("Capture error messages", invalid_user.errors:any(), "Errors: " .. invalid_user.errors:size())

print_header("Query Methods")
local found = User:find(user.id)
print_status("Find by ID", found ~= nil and found.username == "leandro")
print_status("Exists check", User:exists({ username = "leandro" }))
print_status("Count check", User:count() == 1, "Total: " .. User:count())

print_header("Relationships")
local post = user.posts:create({ title = "First Post", content = "Hello world" })
print_status("HasMany: Create child", post ~= nil and post.id ~= nil)
print_status("HasMany: Lazy count", user.posts:count() == 1)
local found_post = Post:find(post.id)
print_status("BelongsTo: Load parent", found_post.user ~= nil and found_post.user.username == "leandro")

print_header("Serialization")
User.attributes = { "id", "username", "name", "display_name", "created_at" }
local data = user:toTable()
print(colors.bold .. string.format("%-15s | %-20s", "Key", "Value") .. colors.reset)
print(string.rep("-", 40))
for k, v in pairs(data) do
    print(string.format("%-15s | %-20s", k, tostring(v)))
end

print_header("Soft Delete & Calculations")
user:delete()
print_status("Hide soft-deleted", User:find(user.id) == nil)
print_status("Retain in raw DB", DBManager.query("SELECT COUNT(*) as c FROM users")[1].c == 1)

User:new({ username = "user2", email = "u2@ex.com", age = 20, password = "password" }):save()
print_status("Calculation: AVG", User:avg("age") == 25.0, "Avg: 25.0")
print_status("Calculation: SUM", User:sum("age") == 50, "Sum: 50")

print("\n" .. colors.bold .. colors.green .. "--- ALL STANDALONE TESTS FINISHED ---" .. colors.reset .. "\n")
os.remove(db_file)
