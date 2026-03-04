local Task = require("app.models.task")
local TasksController = {}

function TasksController:index(ctx)
    local items = Task:all()
    return ctx:view("tasks/index", { tasks = items })
end

function TasksController:show(ctx)
    local item = Task:find(ctx.params.id)
    if not item then return ctx:text("Not Found", 404) end
    return ctx:view("tasks/show", { task = item })
end

function TasksController:new(ctx)
    return ctx:view("tasks/new", { task = Task:new() })
end

function TasksController:edit(ctx)
    local item = Task:find(ctx.params.id)
    if not item then return ctx:text("Not Found", 404) end
    return ctx:view("tasks/edit", { task = item })
end

function TasksController:create(ctx)
    local item = Task:new(ctx.body)
    if item:save() then
        return ctx:redirect("/tasks/" .. item.id .. "?notice=Task was successfully created.")
    else
        return ctx:view("tasks/new", { task = item, alert = "Error creating task" })
    end
end

function TasksController:update(ctx)
    local item = Task:find(ctx.params.id)
    if not item then return ctx:text("Not Found", 404) end
    if item:update(ctx.body) then
        return ctx:redirect("/tasks/" .. item.id .. "?notice=Task was successfully updated.")
    else
        return ctx:view("tasks/edit", { task = item, alert = "Error updating task" })
    end
end

function TasksController:destroy(ctx)
    local item = Task:find(ctx.params.id)
    if item then 
        item:delete()
        return ctx:redirect("/tasks?notice=Task was successfully destroyed.")
    end
    return ctx:redirect("/tasks")
end

return TasksController
