local HomeController = {}

function HomeController:index(ctx)
    return ctx:json({ message = "Welcome to Rio API" })
end

return HomeController
