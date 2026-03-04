local Label = require("app.models.label")
local LabelsController = {}

function LabelsController:index(ctx)
    local labels = Label:all()
    return ctx:json(labels)
end

function LabelsController:show(ctx)
    local label = Label:find(ctx.params.id)
    if not label then return ctx:json({ error = "Label not found" }, 404) end
    return ctx:json(label)
end

function LabelsController:create(ctx)
    local label = Label:new(ctx.body)
    if label:save() then
        return ctx:json(label, 201)
    else
        return ctx:json({ errors = label.errors:all() }, 422)
    end
end

function LabelsController:update(ctx)
    local label = Label:find(ctx.params.id)
    if not label then return ctx:json({ error = "Label not found" }, 404) end
    if label:update(ctx.body) then
        return ctx:json(label)
    else
        return ctx:json({ errors = label.errors:all() }, 422)
    end
end

function LabelsController:destroy(ctx)
    local label = Label:find(ctx.params.id)
    if label then 
        label:delete()
        return ctx:json({ message = "Label deleted successfully" })
    end
    return ctx:json({ error = "Label not found" }, 404)
end

return LabelsController
