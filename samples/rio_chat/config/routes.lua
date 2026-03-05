return function(app)
    app:get("/", "Rooms@show")
    app:ws("/cable/chat", "ChatChannel")
end
