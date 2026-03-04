#!/bin/bash

# test_seeds.sh - Script to test post seeds

echo "--- Dropping Database ---"
rio db:drop

echo -e "\n--- Running Migrations ---"
rio db:migrate

echo -e "\n--- Running Seeds ---"
rio db:seed

echo -e "\n--- Verifying Data ---"
rio runner '
local Post = require("app.models.post")
local cjson = require("cjson")
local posts = Post:all()
local simple_posts = {}

print("id|title|published|price|priority")
for _, post in ipairs(posts) do
    -- SQLite boolean fix (uses 0/1)
    local is_published = (post.published == 1 or post.published == true)
    
    -- Table format print
    print(post.id .. "|" .. post.title .. "|" .. (is_published and "true" or "false") .. "|" .. post.price .. "|" .. post.priority)
    
    -- Prepare for JSON
    table.insert(simple_posts, {
        id = post.id,
        title = post.title,
        published = is_published,
        price = post.price,
        priority = post.priority
    })
end

print("\nJSON:")
print(cjson.encode(simple_posts))
'
