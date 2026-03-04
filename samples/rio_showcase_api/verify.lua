-- samples/rio_showcase_api/verify.lua
require("bootstrap")
local User = require("app.models.user")
local Project = require("app.models.project")
local Label = require("app.models.label")
local DB = require("rio.database.manager")
local rio = require("rio")

-- Initialize DB manually for script
local db_config = require("config.database").development
DB.initialize(db_config)

local app = rio.new(require("config.application"))

print("\n--- Verifying Rio Showcase API ---\n")

-- 1. Test 1:1 (User -> Profile)
local admin = User:find_by({ username = "admin" })
print(string.format("User: %s | Profile Name: %s", admin.username, admin.profile.full_name))

-- 2. Test 1:N (User -> Projects)
print(string.format("User: %s has %d projects", admin.username, admin.projects:count()))
for _, p in ipairs(admin.projects:get()) do
    print("  - Project: " .. p.name)
end

-- 3. Test N:M (Project <-> Labels via Through)
local p1 = Project:find_by({ name = "Project Rio" })
print(string.format("\nProject: %s has labels:", p1.name))
for _, l in ipairs(p1.labels:get()) do
    print(string.format("  - [%s] %s", l.color, l.name))
end

-- 4. Test Reverse N:M
local enhancement = Label:find_by({ name = "Enhancement" })
print(string.format("\nLabel: %s is linked to %d projects", enhancement.name, enhancement.projects:count()))

-- 5. Test Cache Persistence
print("\n--- Testing Level 2 Cache ---")
local key = "test_verification_key"
app.cache:delete(key) -- Ensure fresh start

local function get_data()
    print("  [Cache MISS] Fetching real data...")
    return { status = "ok", timestamp = os.time() }
end

local val1 = app.cache:fetch(key, 60, get_data)
print("Result 1 Timestamp: " .. val1.timestamp)

local val2 = app.cache:fetch(key, 60, get_data)
print("Result 2 Timestamp: " .. val2.timestamp)

if val1.timestamp == val2.timestamp then
    print("✓ Cache HIT successful!")
else
    print("✗ Cache HIT failed!")
end

print("\n--- Verification Complete ---\n")
