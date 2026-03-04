# Rio Framework Samples

This directory contains reference applications built with the **Rio Framework**. These projects are designed to demonstrate the framework's versatility in handling both modern RESTful APIs and classic Full-stack MVC architectures.

## Available Projects

### 1. [Rio Showcase API](./rio_showcase_api)
**Focus:** Pure Backend & High Performance.

This sample demonstrates how to build a robust, JSON-only RESTful API. It is ideal for developers looking to use Rio as a backend for mobile apps or single-page applications (SPA).

- **Key Technologies:** JWT Authentication, PBKDF2 Hashing, Two-Level Caching (Query & Application), and Swagger/OpenAPI documentation.
- **ORM Focus:** Complex relationships including `has_many :through` and automatic join table management.
- **Documentation:** Auto-generated interactive API docs available at `/docs`.

### 2. [Rio Showcase MVC](./rio_showcase_mvc)
**Focus:** Full-stack Web Development & Security.

A complete "Batteries-included" web application with a server-side rendered frontend. It demonstrates the classic web development workflow with forms, sessions, and protected administrative areas.

- **Key Technologies:** Cookie-based Session Management, Role-Based Access Control (RBAC), and Embedded Template Lua (ETL).
- **UI Focus:** Dynamic layouts, reusable partials (Header), and conditional rendering based on user roles and request paths.
- **Admin Area:** A dedicated sub-system for managing users, protected by specialized security middleware.

---

## How to Run the Samples

All samples use **SQLite3** by default for ease of setup.

### Prerequisites
Make sure you have the Rio Framework installed and the SQLite3 driver available:
```bash
luarocks install luasql-sqlite3 --local
```

### Quick Execution
Navigate to the desired project folder and use the Rio CLI:

```bash
# 1. Enter the project
cd rio_showcase_mvc  # or rio_showcase_api

# 2. Setup the database (Migrations + Seeds)
../../bin/rio db:setup

# 3. Start the server
../../bin/rio server
```

## Learning Path
- **New to Rio?** Start with the **MVC Showcase** to understand the core directory structure and template engine.
- **Building an API?** Explore the **API Showcase** to learn about JWT security and performance optimization through caching.
