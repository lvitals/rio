# Rio Framework

Lua web framework with MVC architecture and RESTful API support.

Rio provides a comprehensive environment for building scalable web applications and APIs, offering a structured approach to development with built-in tools for database management, security, and performance.

## Key Features

- **MVC Architecture:** Enforces a clean separation of concerns between data, logic, and presentation layers.
- **Advanced ORM:** Powerful object-relational mapping with support for complex relationships (1:1, 1:N, N:M), dependent deletion, and versioned migrations.
- **Embedded Template Lua (ETL):** An efficient templating engine for embedding Lua logic directly within HTML files.
- **Unified CLI:** Streamlined development workflow with generators for scaffolds, models, controllers, and database management.
- **Enterprise-Grade Security:** Out-of-the-box password hashing (PBKDF2), JWT-based authentication, and automated data protection layers.
- **Two-Level Caching:** Optimized performance via Request-level Query Cache and Persistent Application Cache.
- **API First Design:** First-class support for RESTful services with specialized generators for JSON-only backends.
- **Integrated Testing:** Native integration with Busted for reliable automated testing.

## Quick Start

### 1. Create a New Application
```bash
# Create a full MVC application
rio new my_app --database=sqlite3

# Or create an API-only application
rio new my_api --api --database=postgresql
```

### 2. Generate a Scaffold
Generate a complete CRUD (Model, Migration, Controller, Views, and Tests) in seconds:
```bash
cd my_app
rio generate scaffold Post title:string body:text published:boolean
```

### 3. Setup the Database
```bash
rio db:setup
```

### 4. Start the Server
```bash
rio server
```
Your application will be running at `http://localhost:8080`.

## Local Development

If you are developing the Rio framework itself or want to install it from a local clone, follow these instructions:

### 1. Clone the repository
```bash
git clone https://github.com/lvitals/rio.git
cd rio
```

### 2. Install dependencies & framework locally
On architectures like **Arch Linux**, you must explicitly provide the MySQL include directory:
```bash
luarocks install rio-dev-1.rockspec --local MYSQL_INCDIR=/usr/include/mysql
```

For other systems (e.g., Ubuntu/Debian), installing from the local rockspec usually works out of the box:
```bash
luarocks install rio-dev-1.rockspec --local
```

### 3. Running Tests
By default, running the test suite will run against SQLite and automatically skip MySQL and PostgreSQL if they are not running.

To run the full test suite (including MySQL and PostgreSQL), spin up the test databases using Docker Compose (or Podman):
```bash
# Start the database containers
docker compose up -d   # or: podman-compose up -d

# Run the test suite
chmod +x test/run_tests.sh
./test/run_tests.sh

# Tear down the database containers
docker compose down   # or: podman-compose down
```
This script will automatically configure the correct environment variables and run all test specifications using Busted.

## Documentation

For detailed information on how to use Rio, please refer to the following resources:

- [Installation Guide](INSTALL.md)
- [Full Framework Reference](docs/rio.md)
- [CLI & Commands](docs/rio.md#commands)
- [ORM & Relationships](docs/rio.md#active-record-orm)
- [Security & Authentication](docs/rio.md#security-and-authentication)
- [Templates (ETL)](docs/rio.md#template-engine-etl)

## License

Rio is released under the [MIT License](LICENSE).
