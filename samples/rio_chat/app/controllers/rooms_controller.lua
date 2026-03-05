local RoomsController = {}

function RoomsController:show(ctx)
    return ctx:view("rooms/show")
end

return RoomsController
