local User = require("app.models.user")
local Profile = require("app.models.profile")
local Project = require("app.models.project")
local Label = require("app.models.label")
local ProjectLabel = require("app.models.project_label")
local ui = require("rio.utils.ui")

ui.info("Cleaning database...")
ProjectLabel:raw("DELETE FROM project_labels")
Label:raw("DELETE FROM labels")
Project:raw("DELETE FROM projects")
Profile:raw("DELETE FROM profiles")
User:raw("DELETE FROM users")

ui.info("Seeding Users and Profiles (1:1)...")
local admin = User:create({ 
    username = "admin", 
    password = "password123", 
    email = "admin@rio.dev" 
})
admin:create_profile({ 
    full_name = "Rio Administrator", 
    bio = "The lead developer of Rio framework." 
})

local dev = User:create({ 
    username = "leandro", 
    password = "secret_password", 
    email = "leandro@rio.dev" 
})
dev:create_profile({ 
    full_name = "Leandro Vitals", 
    bio = "Software Engineer and Rio contributor." 
})

ui.info("Seeding Projects (1:N)...")
local p1 = dev.projects:create({ 
    name = "Project Rio", 
    description = "A powerful Lua web framework." 
})
local p2 = dev.projects:create({ 
    name = "ETL Engine", 
    description = "Next-gen templating for Lua." 
})
local p3 = admin.projects:create({ 
    name = "Documentation", 
    description = "Writing the best docs." 
})

ui.info("Seeding Labels and Associations (N:M)...")
local critical = Label:create({ name = "Critical", color = "#FF0000" })
local enhancement = Label:create({ name = "Enhancement", color = "#00FF00" })
local documentation = Label:create({ name = "Docs", color = "#0000FF" })

-- Manually link via the join table (Rio ORM will then handle the :through)
ProjectLabel:create({ project_id = p1.id, label_id = critical.id })
ProjectLabel:create({ project_id = p1.id, label_id = enhancement.id })
ProjectLabel:create({ project_id = p2.id, label_id = enhancement.id })
ProjectLabel:create({ project_id = p3.id, label_id = documentation.id })

ui.box("Seeding Results", function()
    ui.row("Users seeded", User:count())
    ui.row("Profiles seeded", Profile:count())
    ui.row("Projects seeded", Project:count())
    ui.row("Labels seeded", Label:count())
end)
