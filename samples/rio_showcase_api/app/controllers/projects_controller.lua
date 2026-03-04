local Project = require("app.models.project")
local ProjectsController = {}

function ProjectsController:index(ctx)
    local projects = Project:all()
    return ctx:json(projects)
end

function ProjectsController:show(ctx)
    local project = Project:find(ctx.params.id)
    if not project then return ctx:json({ error = "Project not found" }, 404) end
    return ctx:json(project)
end

function ProjectsController:create(ctx)
    local project = Project:new(ctx.body)
    -- In a real scenario, you would associate user_id from context
    if ctx.state.user and ctx.state.user.sub then
        project.user_id = tonumber(ctx.state.user.sub)
    end
    
    if project:save() then
        return ctx:json(project, 201)
    else
        return ctx:json({ errors = project.errors:all() }, 422)
    end
end

function ProjectsController:update(ctx)
    local project = Project:find(ctx.params.id)
    if not project then return ctx:json({ error = "Project not found" }, 404) end
    if project:update(ctx.body) then
        return ctx:json(project)
    else
        return ctx:json({ errors = project.errors:all() }, 422)
    end
end

function ProjectsController:destroy(ctx)
    local project = Project:find(ctx.params.id)
    if project then 
        project:delete()
        return ctx:json({ message = "Project deleted successfully" })
    end
    return ctx:json({ error = "Project not found" }, 404)
end

return ProjectsController
