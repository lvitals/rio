# Installation Guide

This guide will walk you through setting up your environment to develop and run Rio applications.

## Prerequisites

Before installing Rio, you need to have the following software installed on your system:

- **Lua 5.1, 5.2, 5.3, or 5.4**
- **LuaRocks** (the package manager for Lua modules)
- **C compiler** (like `gcc`) and build tools (like `make`)
- **Database libraries** for your chosen driver:
  - **SQLite3:** `libsqlite3-dev`
  - **MySQL/MariaDB:** `libmysqlclient-dev` (or `libmariadb-dev-compat`)
  - **PostgreSQL:** `libpq-dev`

### On Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install lua5.4 luarocks build-essential libsqlite3-dev libmysqlclient-dev libpq-dev
```

### On Arch Linux:
```bash
sudo pacman -Syu
sudo pacman -S lua luarocks base-devel sqlite mariadb-libs postgresql-libs
```

## Install Rio Framework

You can install Rio via LuaRocks. For development purposes, it's recommended to install it locally.

### 1. Install via LuaRocks
```bash
# Install the latest stable version
luarocks install rio --local
```

### 2. Configure your Shell Environment
To use the `rio` command and ensure Lua finds your local gems, add the following to your `~/.bashrc` or `~/.zshrc`:

```bash
# Add LuaRocks local bin to PATH
export PATH="$HOME/.luarocks/bin:$PATH"

# Setup Lua paths for local modules (adjust 5.4 to your Lua version)
eval $(luarocks path --lua-version 5.4)
```

Reload your shell:
```bash
source ~/.bashrc  # or source ~/.zshrc
```

## Verify Installation

Once installed, verify that the `rio` command is available:
```bash
rio about
```

## Setting Up Database Drivers

Rio supports multiple database backends. You must install the corresponding LuaSQL driver for your database.

### SQLite3 (Recommended for Development)
```bash
luarocks install luasql-sqlite3 --local
```

### MySQL/MariaDB
```bash
# You may need to provide include and library paths for the installation
luarocks install luasql-mysql MYSQL_INCDIR=/usr/include/mysql MYSQL_LIBDIR=/usr/lib --local
```

### PostgreSQL
```bash
luarocks install luasql-postgres --local
```

## Creating Your First Project

```bash
rio new my_awesome_project --database=sqlite3
cd my_awesome_project
rio db:setup
rio server
```
Open `http://localhost:8080` in your browser.
