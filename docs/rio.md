RIO(1) - General Commands Manual

# NAME

**rio** - Lua web framework with MVC architecture and RESTful API support

# SYNOPSIS

**rio**
*command*
\[*options*]
\[*arguments*]

# DESCRIPTION

The
**rio**
framework is a high-productivity web framework for Lua.
It follows the Model-View-Controller (MVC) pattern and provides advanced tools
for security, persistence, and automation via its command-line interface.

This manual covers the CLI commands, the Active Record ORM, security features,
template engine (ETL), and the caching system.

# COMMANDS

**new** *name* \[**--database=DB** \[**--api**]]

> Creates a new Rio application structure.
> The
> **--api**
> option disables view rendering and configures the app for JSON responses only.
> Supported databases:
> *postgresql*, *mysql*, *sqlite3*, *none*.

**server** \[**-p** *port* \[**-b** *binding* \[**-e** *environment* \[**-d** \[**--pid=FILE**]]]]]

> Starts the Rio web server.
> Options:

> **-p,** **--port=** *PORT*

> > Set the port (default: 8080).

> **-b,** **--binding=** *IP*

> > Set the IP address (default: 0.0.0.0).

> **-e,** **--environment=** *ENV*

> > Set the environment (development, test, production).

> **-d,** **--daemon**

> > Run the server in the background as a daemon.

> **--pid=** *FILE*

> > Specify the PID file for daemon mode (default: tmp/pids/server.pid).

**console** \[**-e** *environment* \[**-s**]]

> Opens an interactive Rio console (REPL) with the application environment loaded.
> All models are automatically loaded into the global scope.
> Options:

> **-e,** **--environment=** *ENV*

> > Set the environment (default: development).

> **-s,** **--sandbox**

> > Rollback any database changes upon exiting.

> Available objects in console:
> *app*
> (application instance),
> *db*
> (database helpers),
> *helper*
> (view utilities),
> *reload*
> (reload project modules),
> *pp*
> (pretty-print),
> *history*
> (command history),
> *clear*
> (clear screen).

**runner** \[**-e** *environment* \[**--skip-executor** *code|file*]]

> Executes Lua code or a file within the context of the Rio application.
> The
> **--skip-executor**
> option skips loading models and connecting to the database.

**routes** \[**-c** *controller* \[**-g** *pattern* \[**-E**]]]

> Lists all defined routes, URI patterns, and handlers.
> Options:

> **-c,** **--controller=** *NAME*

> > Filter routes by controller name.

> **-g,** **--grep=** *PATTERN*

> > Filter routes by matching pattern in verb, URI, or controller.

> **-E,** **--expanded**

> > Display detailed information in expanded format.

**test** \[*args*]

> Executes the application's test suite using Busted.
> Additional arguments are passed directly to Busted.

**about**

> Displays system information, versions, and database status.

**stats**

> Shows project statistics (LOC, methods, Modules, and code-to-test ratio).

**initializers**

> Lists the order in which the application's initialization scripts are loaded.

**scaffold** *Name* \[*fields*]

> Alias for
> **generate scaffold**.

**resource** *Name* \[*fields*]

> Alias for
> **generate resource**.

**help** \[*command* \[*subcommand*]]

> Displays help for a command or a specific subcommand.

# GENERATORS AND DESTRUCTORS

Generators create boilerplate code, while destructors remove it.

**generate scaffold** *Name* \[*fields*]

> Creates a full CRUD (Model, Migration, Controller, Views, Tests, and Routes).
> Supports namespaces using
> *::*
> (e.g.,
> *Admin::Post*).
> Controllers and views will be organized into subdirectories.

**generate resource** *Name* \[*fields*]

> Creates a scaffold without the Views. Supports namespaces.

**generate** | **destroy model** *Name* \[*fields*]

> Creates or removes a Model and its corresponding Migration.
> Models are created in the flat
> *app/models/*
> directory.

**generate** | **destroy migration** *Name* \[*fields*]

> Creates or removes a database migration file.

**generate** | **destroy controller** *Name* \[*actions*]

> Creates or removes a Controller and its corresponding Tests. Supports namespaces.

**generate channel** *Name*

> Creates a WebSocket channel and adds its route.

Fields are defined as
*name:type{options}*.
Available types:
*string*, *text*, *integer*, *decimal*, *float*, *boolean*, *date*, *datetime*, *references*.

# DATABASE COMMANDS

Commands prefixed with
**db:**
manage the database schema and lifecycle.

**db:create**, **db:drop**

> Creates or removes the physical database.

**db:migrate**, **db:rollback**

> Applies or reverts schema migrations.

**db:status**, **db:version**

> Checks the status of migrations and the current schema version.

**db:setup**, **db:reset**

> Performs a full setup or reset (Create, Migrate, Seed).

**db:prepare**

> Ensures the database exists and is fully migrated.

**db:seed**, **db:seed:replant**

> Populates initial data (replant clears tables first).

**db:cache:clear**

> Clears database metadata and logical caches.

**db:system:change** **--to=** *adapter*

> Interactively changes the database adapter in config/database.lua.

# MAINTENANCE AND MAILBOX

**tmp:create**

> Creates temporary directories for cache, sockets, and pids.

**tmp:clear**

> Clears all cache, sockets, and screenshot files.

**tmp:cache:clear**, **tmp:sockets:clear**, **tmp:screenshots:clear**, **tmp:pids:clear**

> Clears specific temporary directories.

**middleware**

> Lists active and available middlewares.

**middleware:create** *name*

> Generates a new custom middleware file in app/middleware/.

**middleware:use** *name*

> Enables a middleware in config/middlewares.lua.

**middleware:unuse** *name*

> Disables a middleware in config/middlewares.lua.

**middleware:rm** *name*

> Deletes a local middleware file and disables it.

**mailbox:install**

> Sets up the Mailbox system (folders, base class, and migrations).

**mailbox:ingress:** *provider*

> Relay an inbound email from a provider (postfix, exim, qmail) to Rio.

# ROUTING

Routes are defined in
*config/routes.lua*.

## Basic Methods

**app:get(path, handler)**

**app:post(path, handler)**

**app:put(path, handler)**

**app:patch(path, handler)**

**app:delete(path, handler)**

**app:ws(path, channel)**

## Grouping and Resources

**app:group(prefix, function(app) ... end)**

> Nests routes under a common URI prefix.

**app:resources(name, \[controller])**

> Generates RESTful routes for a resource (index, show, new, edit, create, update, destroy).

# ACTIVE RECORD ORM

The Rio ORM manages complex relationships and database persistence.

## Configuration

**table\_name**

> Explicitly set the database table name.

**primary\_key**

> Set the primary key (default: "id").

**timestamps**

> Enable/disable created\_at and updated\_at (default: true).

**soft\_deletes**

> When true, records are marked as deleted instead of being removed.

**per\_page**

> Default records per page for pagination (default: 5).

## Relationships

**has\_one**

> Defines a 1:1 relationship.

**has\_many**

> Defines a 1:N relationship.

**belongs\_to**

> Defines the owner of the relationship and foreign keys.

**has\_many :through**

> Defines N:M relationships via a join table.

## Dependent Deletion

The
*dependent = destroy*
option ensures that child records are deleted when the parent is removed.

## Hooks and Transactions

**before\_save**, **before\_create**, **before\_update**

> Callback functions called during the record lifecycle.

**Model.transaction(cb)**

> Executes a callback within a database transaction.

## Validations

Supported rules:
*presence*, *uniqueness*, *format*, *length*, *numericality*.

# SECURITY AND AUTHENTICATION

Rio focuses on three pillars of security: Hashing, JWT, and Data Protection.

## Password Hashing

Uses PBKDF2 with HMAC-SHA256 via
*rio.utils.hash*.
Passwords should be encrypted in the
*before\_save*
hook of the model.

## JWT Authentication

Provides token-based authentication for APIs.
Tokens are generated using
*auth.generate\_access\_token*
and verified via the
*auth.jwt*
middleware.

## Attribute Protection

Attributes listed in
*Model.hidden*
are automatically removed when converting objects to JSON or arrays.

# TEMPLATE ENGINE (ETL)

Embedded Template Lua (ETL) allows embedding Lua code in HTML.
Files use the
*.etl*
extension.

## Syntax

**&lt;%= expr %&gt;**

> Interpolates with HTML escaping (safe).

**&lt;%- expr %&gt;**

> Interpolates raw HTML (unsafe).

**&lt;% code %&gt;**

> Executes Lua logic (loops, conditionals).

**&lt;%# comment %&gt;**

> Server-side comments.

# CACHE SYSTEM

Rio provides a two-level caching system.

## Query Cache (Level 1)

Stores identical SQL query results during the lifecycle of a single HTTP request.
Automatically cleared after each request.

## Application Cache (Level 2)

Persistent cache shared between requests.
Stores:

**memory**

> Fast RAM storage (volatile).

**file**

> Stored in
> *tmp/cache/*
> (shared between processes).

**null**

> Disables caching.

# ENVIRONMENT

`RIO_ENV`

> Defines the current environment (e.g., development, test, production).

# FILES

*config/routes.lua*

> Routing configuration.

*config/database.lua*

> Database settings.

*app/models/*

> Application models.

*app/controllers/*

> Application controllers.

*app/views/*

> ETL templates.

# SEE ALSO

busted(1),
lua(1)

# AUTHORS

The Rio Framework Team.

# BUGS

Report bugs at the official repository.

Linux 6.19.9-arch1-1 - April 2, 2026
