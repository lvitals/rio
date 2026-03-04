return function(app)
    app:get("/hello", function(ctx)
        return ctx:json({
            message = "Hello from Standalone Rio!",
            mode = "standalone",
            server = "rio-builtin"
        })
    end)
end
