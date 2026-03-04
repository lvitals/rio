# Rio Showcase MVC

A full-featured Model-View-Controller (MVC) application built with the **Rio Framework**. This project demonstrates how to build a real-world application with user authentication, administrative privileges, and dynamic content rendering.

## Core Features

- **MVC Architecture:** Robust separation of data (Models), business logic (Controllers), and presentation (ETL Templates).
- **Session-Based Authentication:** Secure login system using HTTP-only cookies and a custom session loader middleware.
- **Role-Based Access Control (RBAC):** 
    - **Standard Users:** Can manage their own tasks.
    - **Administrators:** Full access to an exclusive User Management CRUD to create, edit, or delete system users and toggle admin privileges.
- **Advanced Model Validations:**
    - Automatic password hashing using PBKDF2.
    - Password confirmation matching logic.
    - Presence and uniqueness constraints.
- **Embedded Template Lua (ETL):** High-performance templating with reusable partials (shared header) and conditional UI elements based on user state and current path.
- **Middleware Chain:** 
    - `session_middleware`: Automatically loads the user from cookies.
    - `admin_middleware`: Protects sensitive routes from non-administrative access.

## Project Structure

- `app/models/`: `User.lua` (with custom validations) and `Task.lua`.
- `app/controllers/`: 
    - `Auth@`: Handles login/logout flow.
    - `Tasks@`: General CRUD for application tasks.
    - `AdminUsers@`: Specialized CRUD for user administration.
- `app/views/`: ETL templates organized by resource, including a `shared/` directory for partials.
- `app/middleware/`: Custom logic for session handling and security layers.
- `db/migrate/`: Versioned schema changes, including the evolution from basic users to admin roles.

## Getting Started

### 1. Prerequisites
Ensure you have the Rio Framework and the SQLite3 driver installed:
```bash
luarocks install luasql-sqlite3 --local
```

### 2. Setup the Database
Create the database, run all migrations, and populate the system with the initial administrator:
```bash
rio db:setup
```

### 3. Launch the Application
```bash
rio server
```
Visit `http://localhost:8080` in your browser.

## Docker & OpenResty

This project includes a Docker configuration to run with OpenResty as a reverse proxy.

### 1. Start the Containers
```bash
docker-compose up --build
```

### 2. Access the MVC App
- **Web Portal:** `http://localhost:8081`
- **Health Status:** `http://localhost:8081/status`

The containers persist your SQLite database in the `./db` directory.

## Credentials

The system comes pre-seeded with an administrator account:
- **Username:** `admin`
- **Password:** `password123`

## Key Concepts Demonstrated

### Route Protection
The application uses nested route groups in `config/routes.lua` to apply different layers of security:
1. **Public:** Login and Landing pages.
2. **Protected:** Tasks CRUD (requires being logged in).
3. **Admin:** User Management (requires being logged in AND having the `is_admin` flag).

### Smart UI
The navigation bar (`app/views/shared/_header.etl`) dynamically adjusts based on the user's role and the current page, hiding the login button when on the login screen and showing the "User Management" link only to administrators.
