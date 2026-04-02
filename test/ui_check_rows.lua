local ui = require("rio.utils.ui")
local colors = require("rio.utils.compat").colors

ui.box("Relationship Status", function()
    ui.status("User Database", true, "Connection established")
    ui.status("Redis Cache", false, "Timed out after 5s")
    ui.status("Worker Queue", true, "15 messages pending")
    ui.row("App Version", "1.2.3-beta")
    ui.row("Environment", "production")
    ui.row("License", "Enterprise License (Valid until 2027)")
end)
