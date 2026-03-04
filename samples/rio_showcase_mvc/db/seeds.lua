local User = require("app.models.user")
local Task = require("app.models.task")

print("Cleaning database...")
Task:raw("DELETE FROM tasks")
User:raw("DELETE FROM users")

print("Creating admin user...")
local admin = User:create({
    username = "admin",
    password = "password123",
    password_confirmation = "password123", -- Requerido pela nova validação!
    email = "admin@example.com",
    is_admin = true
})

print("Creating sample tasks...")
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

print("-----------------------------------------------")
print("Seeding completed successfully!")
print("Users: " .. User:count())
print("Tasks: " .. Task:count())
print("-----------------------------------------------")
