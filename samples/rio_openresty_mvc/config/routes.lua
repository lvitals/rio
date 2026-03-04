-- config/routes.lua
-- Defines the application's routes using the Rio router.

return function(app)
    -- Format: "ControllerName@actionName" enables auto-documentation
    app:get("/", "Home@index")
    app:resources("posts")
end