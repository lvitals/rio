local HomeController = {}

function HomeController:index(ctx)
    if ctx.state.user then
        return ctx:redirect("/tasks")
    else
        return ctx:redirect("/login")
    end
end

return HomeController
