local HomeController = {}

HomeController.openapi = {
    index = {
        hidden = true
    }
}

function HomeController:index(ctx)
    return ctx:json({ message = "Welcome to Rio API" })
end

return HomeController
