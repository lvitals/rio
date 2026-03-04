local Post = require("app.models.post")
local PostsController = {}

function PostsController:index(ctx)
    local items = Post:all()
    return ctx:view("posts/index", { posts = items })
end

function PostsController:show(ctx)
    local item = Post:find(ctx.params.id)
    if not item then return ctx:text("Not Found", 404) end
    return ctx:view("posts/show", { post = item })
end

function PostsController:new(ctx)
    return ctx:view("posts/new", { post = Post:new() })
end

function PostsController:edit(ctx)
    local item = Post:find(ctx.params.id)
    if not item then return ctx:text("Not Found", 404) end
    return ctx:view("posts/edit", { post = item })
end

function PostsController:create(ctx)
    local item = Post:new(ctx.body)
    if item:save() then
        return ctx:redirect("/posts/" .. item.id .. "?notice=Post was successfully created.")
    else
        return ctx:view("posts/new", { post = item, alert = "Error creating post" })
    end
end

function PostsController:update(ctx)
    local item = Post:find(ctx.params.id)
    if not item then return ctx:text("Not Found", 404) end
    if item:update(ctx.body) then
        return ctx:redirect("/posts/" .. item.id .. "?notice=Post was successfully updated.")
    else
        return ctx:view("posts/edit", { post = item, alert = "Error updating post" })
    end
end

function PostsController:destroy(ctx)
    local item = Post:find(ctx.params.id)
    if item then 
        item:delete()
        return ctx:redirect("/posts?notice=Post was successfully destroyed.")
    end
    return ctx:redirect("/posts")
end

return PostsController