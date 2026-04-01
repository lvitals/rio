-- test/ui_demo.lua
-- Visual verification of the new UI alert system

local ui = require("rio.utils.ui")

print("\n--- STANDALONE ALERTS ---")
ui.alert("primary", "Starting Rio Framework...")
ui.success("Server started successfully")
ui.error("Database connection failed")
ui.warn("Configuration file not found")
ui.info("Using default settings")
ui.alert("secondary", "Background task running")
ui.alert("light", "Optional update available")
ui.alert("dark", "System maintenance scheduled")

print("\n--- ALERTS WITH TITLES ---")
ui.alert_title("success", "Database", "Connected to PostgreSQL")
ui.alert_title("danger", "Migration", "Failed at step 42")
ui.alert_title("warning", "Cache", "Memory limit reached")

print("\n--- BOXED UI WITH ALERTS ---")
ui.box("System Status", function()
    ui.alert("primary", "Rio Framework")
    ui.text("Checking components...")
    ui.success("Core engine initialized")
    ui.success("Middleware stack ready")
    ui.warn("Some plugins are outdated")
    ui.error("Storage disk is 95% full")
    ui.alert("info", "Please check the logs for details")
end)

print("\n--- BACKWARD COMPATIBILITY ---")
ui.info("Direct info message")
ui.info("Connected to 127.0.0.1", "NETWORK")
