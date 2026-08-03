-- rio/lib/rio/cli/help.lua
-- Help screens for Rio CLI commands.

local M = {}

function M.general(ctx)
    ctx.ui.header("Rio Framework CLI")
    ctx.ui.line("Usage: rio <command> [subcommand] [arguments]", ctx.colors.yellow)

    ctx.ui.box("Core Commands", function()
        ctx.ui.row("new <project_name>", "Create a new Rio project")
        ctx.ui.row("server [options]", "Start the Rio web server")
        ctx.ui.row("console [options]", "Open an interactive Rio console")
        ctx.ui.row("test [args]", "Run Busted tests")
        ctx.ui.row("runner <code|file>", "Run Lua code in app context")
        ctx.ui.row("routes [options]", "List defined application routes")
        ctx.ui.row("middleware", "Manage the middleware stack")
        ctx.ui.row("db:<subcommand>", "Manage database")
        ctx.ui.row("generate <type>", "Generate app code")
        ctx.ui.row("destroy <type>", "Undo a generation")
        ctx.ui.row("stats", "Project statistics (LOC, methods)")
        ctx.ui.row("initializers", "List application initializers")
        ctx.ui.row("about", "Application environment info")
        ctx.ui.row("help [command]", "Show help for a command")
    end)

    ctx.ui.line("Run 'rio help <command>' for more information on specific commands.", ctx.colors.dim)
end

function M.middleware(ctx)
    ctx.ui.header("Middleware Management")
    ctx.ui.line("Usage: rio middleware[:subcommand] [args]", ctx.colors.yellow)

    ctx.ui.box("Subcommands", function()
        ctx.ui.row("middleware", "List the application middleware stack")
        ctx.ui.row("middleware:create <name>", "Generate a new middleware file")
        ctx.ui.row("middleware:use <name>", "Enable a middleware in config")
        ctx.ui.row("middleware:unuse <name>", "Disable a middleware in config")
        ctx.ui.row("middleware:rm <name>", "Delete a local middleware file")
    end)

    ctx.ui.info("Core names: logger, security, cors, auth, static")
    ctx.ui.line("Example: rio middleware:use logger", ctx.colors.dim)
end

function M.generate(ctx)
    ctx.ui.header("Resource Generation")
    ctx.ui.line("Usage: rio generate <type> <name> [options]", ctx.colors.yellow)

    ctx.ui.box("Available Generators", function()
        ctx.ui.row("controller <name>", "Generate a new controller")
        ctx.ui.row("model <name>", "Generate a model and migration")
        ctx.ui.row("migration <name>", "Generate a new migration")
        ctx.ui.row("scaffold <name>", "Full CRUD generation")
        ctx.ui.row("resource <name>", "Model, migration, controller & routes")
        ctx.ui.row("channel <name>", "Generate a WebSocket channel")
    end)

    ctx.ui.line("Example: rio generate model Product name:string", ctx.colors.dim)
end

function M.destroy(ctx)
    ctx.ui.header("Resource Destruction")
    ctx.ui.line("Usage: rio destroy <type> <name>", ctx.colors.yellow)

    ctx.ui.box("Available Destroyers", function()
        ctx.ui.row("controller <name>", "Destroy a controller")
        ctx.ui.row("model <name>", "Destroy a model and its migration")
        ctx.ui.row("migration <name>", "Destroy a migration file")
    end)

    ctx.ui.line("Example: rio destroy model Product", ctx.colors.dim)
end

function M.test(ctx)
    ctx.ui.header("Test Runner")
    ctx.ui.line("Usage: rio test [options] [busted_options]", ctx.colors.yellow)

    ctx.ui.info("Runs Busted terminal output by default.")
    ctx.ui.info("Formats: --format=terminal or --format=json.")
    ctx.ui.info("Use --report for Rio's compact report or --quiet for summary-only terminal output.")
    ctx.ui.info("--debug prints the shell command.")
    ctx.ui.line("Example: rio test --report test/cli", ctx.colors.dim)
end

function M.db(ctx)
    ctx.ui.header("Database Management")
    ctx.ui.line("Usage: rio db:<subcommand> [options]", ctx.colors.yellow)

    ctx.ui.box("Available Subcommands", function()
        ctx.ui.row("db:drivers", "Show optional driver status")
        ctx.ui.row("db:install", "Install database driver")
        ctx.ui.row("db:uninstall", "Remove database driver")
        ctx.ui.row("db:create", "Create DB for current environment")
        ctx.ui.row("db:drop", "Delete DB for current environment")
        ctx.ui.row("db:migrate", "Run pending migrations")
        ctx.ui.row("db:rollback", "Revert the last migration")
        ctx.ui.row("db:status", "Show status of all migrations")
        ctx.ui.row("db:version", "Retrieve current schema version")
        ctx.ui.row("db:prepare", "Run setup or migrate as needed")
        ctx.ui.row("db:setup", "Create DB, load schema and seed")
        ctx.ui.row("db:reset", "Drop, recreate and seed database")
        ctx.ui.row("db:system:change", "Switch adapter (e.g. --to=mysql)")
        ctx.ui.row("db:seed", "Run seed file (db/seeds.lua)")
        ctx.ui.row("db:seed:replant", "Truncate all tables and re-seed")
    end)

    ctx.ui.line("Examples: rio db:install sqlite | rio db:uninstall sqlite", ctx.colors.dim)
    ctx.ui.line("Example: rio db:migrate", ctx.colors.dim)
end

function M.new(ctx)
    ctx.ui.header("Project Creation")
    ctx.ui.line("Usage: rio new <project_name> [options]", ctx.colors.yellow)

    ctx.ui.info("Creates a new Rio project with a default directory structure.")

    ctx.ui.box("Options", function()
        ctx.ui.row("--database=ADAPTER", ctx.db_drivers.supported_names() .. ", none")
        ctx.ui.row("--api", "Configure for API-only use")
    end)

    ctx.ui.line("Example: rio new my_app --database=sqlite3", ctx.colors.dim)
end

function M.routes(ctx)
    ctx.ui.header("Application Routes")
    ctx.ui.line("Usage: rio routes [options]", ctx.colors.yellow)

    ctx.ui.info("Lists all defined routes in the application.")

    ctx.ui.box("Options", function()
        ctx.ui.row("-c, --controller=NAME", "Filter by controller name")
        ctx.ui.row("-g, --grep=PATTERN", "Filter by matching pattern")
        ctx.ui.row("-E, --expanded", "Show detailed format")
    end)
end

function M.console(ctx)
    ctx.ui.header("Interactive Console")
    ctx.ui.line("Usage: rio console [options]", ctx.colors.yellow)

    ctx.ui.info("Opens an interactive Lua console with the Rio environment.")

    ctx.ui.box("Options", function()
        ctx.ui.row("-e, --environment=ENV", "App environment (default: dev)")
        ctx.ui.row("-s, --sandbox", "Rollback DB changes on exit")
    end)

    ctx.ui.box("Available Objects", function()
        ctx.ui.row("app", "Application instance for testing")
        ctx.ui.row("helper", "View utilities and helpers")
        ctx.ui.row("<ModelName>", "All your application models")
    end)
end

function M.stats(ctx)
    ctx.ui.header("Project Statistics")
    ctx.ui.line("Usage: rio stats", ctx.colors.yellow)
    ctx.ui.info("Displays project statistics including Lines of Code (LOC) and methods.")
end

function M.about(ctx)
    ctx.ui.header("Environment Info")
    ctx.ui.line("Usage: rio about", ctx.colors.yellow)
    ctx.ui.info("Displays detailed information about the environment and versions.")
end

function M.initializers(ctx)
    ctx.ui.header("Application Initializers")
    ctx.ui.line("Usage: rio initializers", ctx.colors.yellow)
    ctx.ui.info("Lists all application initializers in invocation order.")
end

function M.mailbox(ctx)
    ctx.ui.header("Mailbox Management")
    ctx.ui.line("Usage: rio mailbox:<subcommand> [args]", ctx.colors.yellow)

    ctx.ui.box("Subcommands", function()
        ctx.ui.row("mailbox:install", "Install the Mailbox system")
        ctx.ui.row("mailbox:ingress:exim", "Relay inbound email from Exim")
        ctx.ui.row("mailbox:ingress:postfix", "Relay inbound email from Postfix")
        ctx.ui.row("mailbox:ingress:qmail", "Relay inbound email from Qmail")
    end)

    ctx.ui.line("Example: rio mailbox:install", ctx.colors.dim)
end

function M.tmp(ctx)
    ctx.ui.header("Temporary Files Management")
    ctx.ui.line("Usage: rio tmp:<subcommand>", ctx.colors.yellow)

    ctx.ui.box("Available Subcommands", function()
        ctx.ui.row("tmp:create", "Create required tmp directories")
        ctx.ui.row("tmp:clear", "Clear all cache and temp files")
        ctx.ui.row("tmp:cache:clear", "Clear application cache")
        ctx.ui.row("tmp:sockets:clear", "Clear domain sockets")
        ctx.ui.row("tmp:screenshots:clear", "Clear test screenshots")
    end)

    ctx.ui.line("Example: rio tmp:clear", ctx.colors.dim)
end

function M.server(ctx)
    ctx.ui.header("Rio Web Server")
    ctx.ui.line("Usage: rio server [options]", ctx.colors.yellow)

    ctx.ui.box("Options", function()
        ctx.ui.row("-p, --port=PORT", "Port to listen on (default: 8080)")
        ctx.ui.row("-b, --binding=IP", "IP to bind to (default: 0.0.0.0)")
        ctx.ui.row("-e, --environment=ENV", "App environment (default: dev)")
        ctx.ui.row("-d, --daemon", "Run server in background")
        ctx.ui.row("--pid=FILE", "PID file path for daemon mode")
    end)

    ctx.ui.line("Example: rio server -p 3001 -e production -d", ctx.colors.dim)
end

function M.runner(ctx)
    ctx.ui.header("Rio Runner")
    ctx.ui.line("Usage: rio runner [options] <code|file>", ctx.colors.yellow)

    ctx.ui.info("Runs Lua code in the context of the Rio application.")

    ctx.ui.box("Options", function()
        ctx.ui.row("-e, --environment=ENV", "App environment (default: dev)")
        ctx.ui.row("--skip-executor", "Skip loading models and DB")
    end)

    ctx.ui.line("Example: rio runner \"print(User:count())\"", ctx.colors.dim)
    ctx.ui.line("Example: rio runner scripts/task.lua", ctx.colors.dim)
end

return M
