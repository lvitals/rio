# Rio Showcase API

A comprehensive demonstration of the **Rio Framework**, showcasing advanced features including JWT authentication, complex ORM relationships, two-level caching, and auto-generated OpenAPI documentation.

## Features Demonstrated

- **RESTful API Architecture:** Pure JSON-only backend.
- **JWT Authentication:** Secure token-based access with password hashing (PBKDF2).
- **Advanced ORM (Active Record):**
    - **1:1 Relationship:** `User` has one `Profile`.
    - **1:N Relationship:** `User` has many `Projects`.
    - **N:M Relationship:** `Project` has many `Labels` through `ProjectLabel` (using `has_many :through`).
    - **Dependent Deletion:** Automatic cleanup of child records and join tables.
    - **Validations:** Server-side data integrity rules for all models.
- **Two-Level Caching:**
    - **Level 1 (Query Cache):** Request-level SQL result caching.
    - **Level 2 (Application Cache):** Persistent file-based caching for expensive operations (see `StatsController`).
- **OpenAPI / Swagger:** Automatic documentation generation with request/response examples.

## Project Structure

- `app/models/`: Database models with relationships and validations.
- `app/controllers/`: API logic, including an `AuthController` and a cached `StatsController`.
- `config/routes.lua`: Centralized routing using the `"Controller@action"` format.
- `db/migrate/`: Versioned database schema.
- `db/seeds.lua`: Sample data for testing relationships.

## Getting Started

### 1. Installation
Ensure you have the Rio Framework installed. Then, install the SQLite3 driver:
```bash
luarocks install luasql-sqlite3 --local
```

### 2. Database Setup
Initialize the database, run migrations, and load seed data:
```bash
rio db:setup
```

### 3. Run the Server
```bash
rio server
```
The API will be available at `http://localhost:8080`.

## API Documentation

Rio automatically generates interactive documentation. Once the server is running, visit:
- **Swagger UI:** `http://localhost:8080/docs`
- **OpenAPI Spec:** `http://localhost:8080/openapi.json`

## Testing & Verification

### Manual Verification
Run the included verification script to test ORM relationships and Level 2 Cache:
```bash
lua verify.lua
```

### Automated Tests
Run the project's test suite using Busted:
```bash
rio test
```

## Key API Endpoints

- `POST /auth/login`: Authenticate and receive a JWT.
- `GET /api/me`: Get current user info (Requires JWT).
- `GET /api/stats`: Get system statistics (Uses Level 2 Cache).
- `GET /api/projects`: List projects with their owners.
- `GET /api/labels`: List available labels.
