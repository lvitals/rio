local HomeController = {}

function HomeController:index(ctx)
    ctx:view("home/index")
end

return HomeController
