-- db/seeds.lua
-- This file is used to seed the database with initial data.
local Post = require("app.models.post")

-- Deleting existing posts if any to avoid duplicates in re-seeding (optional)
-- Post:delete_all()

Post:create({
    title = "Getting Started with Rio Framework",
    body = "Rio is a modern MVC framework for OpenResty written in Lua. It provides a robust set of features for building web applications.",
    published = true,
    price = 0.0,
    priority = 1
})

Post:create({
    title = "Why Lua is Great for Web Development",
    body = "Lua is a powerful, efficient, lightweight, embeddable scripting language. Combined with OpenResty, it's incredibly fast.",
    published = true,
    price = 19.99,
    priority = 2
})

Post:create({
    title = "Advanced Nginx Configuration",
    body = "Understanding how Nginx works behind the scenes is crucial for optimizing your OpenResty applications.",
    published = false,
    price = 49.90,
    priority = 3
})

Post:create({
    title = "Database Migrations in Rio",
    body = "Managing your database schema is easy with Rio's built-in migration system.",
    published = true,
    price = 9.95,
    priority = 4
})

Post:create({
    title = "Building a RESTful API",
    body = "Learn how to build high-performance RESTful APIs using Rio and OpenResty.",
    published = true,
    price = 25.00,
    priority = 5
})

print("Successfully seeded posts!")
