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

**server** \[**-p** *port* \[**-b** *binding* \[**-e** *environment* \[**-d**]]]]

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

**console** \[**-s**]

> Opens a REPL (interactive console) with the application environment loaded.
> The
> **-s,** **--sandbox**
> option rolls back any database changes upon exiting.

**runner** \[**-e** *environment* \[**--skip-executor** *code|file*]]

> Executes Lua code or a file within the context of the Rio application.

**routes** \[**-c** *controller* \[**-g** *pattern* \[**-E**]]]

> Lists all defined routes, URI patterns, and handlers.

**test**

> Executes the application's test suite using Busted.

**about**

> Displays system information and database status.

**stats**

> Shows project statistics (LOC, methods, code-to-test ratio).

**initializers**

> Lists the order in which the application's initialization scripts are loaded.

# GENERATORS

Generators create boilerplate code for models, controllers, and resources.

**generate scaffold** *Name* \[*fields*]

> Creates a full CRUD (Model, Migration, Controller, Views, Tests, and Routes).

**generate model** *Name* \[*fields*]

> Creates a Model and its corresponding Migration.

**generate migration** *Name* \[*fields*]

> Creates a new database migration file.

**generate controller** *Name* \[*actions*]

> Creates a Controller and its corresponding Tests.

**generate resource** *Name* \[*fields*]

> Creates a scaffold without the Views.

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

> Changes the database adapter in config/database.lua.

# ACTIVE RECORD ORM

The Rio ORM manages complex relationships and database persistence.

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

Linux 6.18.13-arch1-1 - March 3, 2026
