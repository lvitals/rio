local User = require("app.models.user")
local Task = require("app.models.task")
local ui = require("rio.utils.ui")

ui.info("Cleaning database...")
Task:raw("DELETE FROM tasks")
User:raw("DELETE FROM users")

ui.info("Creating admin user...")
local admin = User:create({
    username = "admin",
    password = "password123",
    password_confirmation = "password123",
    email = "admin@example.com",
    is_admin = true
})

ui.info("Creating sample tasks...")
Task:create({
    title = "Install Rio Framework",
    description = "Follow the installation guide in INSTALL.md",
    status = "completed"
})

Task:create({
    title = "Explore MVC Example",
    description = "Check out controllers, views, and models in this showcase.",
    status = "in_progress"
})

Task:create({
    title = "Build something amazing",
    description = "Use Rio to create your next big project.",
    status = "pending"
})

ui.box("Seeding Summary", function()
    ui.status("Users created", true, User:count())
    ui.status("Tasks created", true, Task:count())
end)
