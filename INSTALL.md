# Installation Guide

This guide will walk you through setting up your environment to develop and run Rio applications.

## Prerequisites

Before installing Rio, you need to have the following software installed on your system:

- **Lua 5.1, 5.2, 5.3, or 5.4**
- **LuaRocks** (the package manager for Lua modules)
- **C compiler** (like `gcc`) and build tools (like `make`)
- **Database libraries only when installing a database driver:**
  - **SQLite3:** `libsqlite3-dev`
  - **MySQL/MariaDB:** `libmysqlclient-dev` (or `libmariadb-dev-compat`)
  - **PostgreSQL:** `libpq-dev`

### On Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install lua5.4 luarocks build-essential
```

### On Arch Linux:
```bash
sudo pacman -Syu
sudo pacman -S lua luarocks base-devel m4 openssl pkgconf
```

## Troubleshooting Build Issues

If you encounter errors during installation, especially when installing dependencies like `cqueues` or `luaossl`, it is often due to missing native build tools or libraries.

### "m4: command not found"
This happens during the installation of `cqueues`. Install `m4`:
- **Ubuntu/Debian:** `sudo apt-get install m4`
- **Arch Linux:** `sudo pacman -S m4`

### "openssl/evp.h: No such file or directory"
This happens during the installation of `luaossl` or `luasec`. Install OpenSSL development headers:
- **Ubuntu/Debian:** `sudo apt-get install libssl-dev`
- **Arch Linux:** `sudo pacman -S openssl`

### "Database driver installation fails"
If `luasql-mysql` or `luasql-postgres` fail to install, ensure you have the correct client libraries installed (see Prerequisites). For MySQL on some systems, you might need to specify the include and library paths:
```bash
rio db:install mysql MYSQL_INCDIR=/usr/include/mysql MYSQL_LIBDIR=/usr/lib
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

Rio supports multiple database backends. The framework installs without database drivers; install the corresponding LuaSQL driver only for the database your app uses.

Check driver status:
```bash
rio db:drivers
```

Remove an unused driver:
```bash
rio db:uninstall sqlite
```

### SQLite3 (Recommended for Development)
```bash
rio db:install sqlite
```

### MySQL/MariaDB
```bash
rio db:install mysql
```

### PostgreSQL
```bash
rio db:install postgresql
```

## Creating Your First Project

```bash
rio new my_awesome_project --database=sqlite3
cd my_awesome_project
rio db:install sqlite
rio db:setup
rio server
```
Open `http://localhost:8080` in your browser.
