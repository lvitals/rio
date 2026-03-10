-- samples/rio_showcase_api/verify.lua
require("bootstrap")
local User = require("app.models.user")
local Project = require("app.models.project")
local Label = require("app.models.label")
local DB = require("rio.database.manager")
local rio = require("rio")
local ui = require("rio.utils.ui")

-- Initialize DB manually for script
local db_config = require("config.database").development
DB.initialize(db_config)

local app = rio.new(require("config.application"))

ui.header("Verifying Rio Showcase API")

ui.box("ORM Relationships Test", function()
    -- 1. Test 1:1 (User -> Profile)
    local admin = User:find_by({ username = "admin" })
    if admin then
        ui.row("User Profile (1:1)", string.format("%s -> %s", admin.username, admin.profile.full_name))
    else
        ui.status("User Profile (1:1)", false, "Admin user not found")
    end

    -- 2. Test 1:N (User -> Projects)
    if admin then
        local projects_count = admin.projects:count()
        ui.row("User Projects (1:N)", string.format("%s owns %d projects", admin.username, projects_count))
        for _, p in ipairs(admin.projects:get()) do
            ui.text("    - " .. p.name, ui.colors.cyan)
        end
    end

    -- 3. Test N:M (Project <-> Labels via Through)
    local p1 = Project:find_by({ name = "Project Rio" })
    if p1 then
        ui.row("Project Labels (N:M)", p1.name)
        for _, l in ipairs(p1.labels:get()) do
            ui.text(string.format("    - [%s] %s", l.color, l.name), ui.colors.cyan)
        end
    end

    -- 4. Test Reverse N:M
    local enhancement = Label:find_by({ name = "Enhancement" })
    if enhancement then
        ui.row("Label to Projects (N:M)", string.format("'%s' is on %d projects", enhancement.name, enhancement.projects:count()))
    end
end)

ui.box("Level 2 Cache Test", function()
    local key = "test_verification_key"
    app.cache:delete(key) -- Ensure fresh start

    local function get_data()
        ui.info("[Cache MISS] Fetching real data...")
        return { status = "ok", timestamp = os.time() }
    end

    local val1 = app.cache:fetch(key, 60, get_data)
    ui.row("Result 1 Timestamp", val1.timestamp)

    -- Simulating a very small delay
    os.execute("sleep 1")

    local val2 = app.cache:fetch(key, 60, get_data)
    ui.row("Result 2 Timestamp", val2.timestamp)

    if val1.timestamp == val2.timestamp then
        ui.status("Cache Consistency", true, "Cache HIT successful")
    else
        ui.status("Cache Consistency", false, "Cache HIT failed")
    end
end)

print()
