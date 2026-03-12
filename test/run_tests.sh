#!/bin/bash

# run_tests.sh
# Automates dependency installation and test execution across multiple Lua versions.

# Ensure we're in the project root relative to the script's location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

# LUA_VERSIONS=("5.4" "5.3" "5.2" "5.1")
LUA_VERSIONS=("5.4")
ROCKSPEC="rio-dev-1.rockspec"

echo "Rio Full Matrix Test Suite"
echo "============================"

# Detect MySQL directories
MYSQL_INC="/usr/include/mysql"
MYSQL_LIB="/usr/lib"

for VER in "${LUA_VERSIONS[@]}"; do
    LUA_BIN="lua$VER"
    if command -v $LUA_BIN &> /dev/null; then
        echo -e "\n\033[1;34m>>> Testing with Lua $VER <<<\033[0m"
        
        echo "Installing dependencies for Lua $VER..."
        luarocks --lua-version="$VER" install luasql-mysql MYSQL_INCDIR=$MYSQL_INC MYSQL_LIBDIR=$MYSQL_LIB --local > /dev/null 2>&1
        luarocks --lua-version="$VER" install luasql-postgres --local > /dev/null 2>&1
        luarocks --lua-version="$VER" install luasql-sqlite3 --local > /dev/null 2>&1
        luarocks --lua-version="$VER" install "$ROCKSPEC" --local --force --only-deps > /dev/null 2>&1
        
        echo "Installing Rio local code..."
        luarocks --lua-version="$VER" make "$ROCKSPEC" --local --force > /dev/null 2>&1

        echo "Configuring environment for Lua $VER..."
        unset LUA_PATH LUA_CPATH
        eval "$(luarocks --lua-version="$VER" path)"
        
        # Absolute priority for local lib/ folder
        export LUA_PATH="./lib/?.lua;./lib/?/init.lua;./?.lua;$LUA_PATH"
        
        echo "Running tests with $LUA_BIN interpreter..."
        $LUA_BIN ./bin/rio test
        

        if [ $? -eq 0 ]; then
            echo -e "\033[1;32m✓ Lua $VER: PASS\033[0m"
        else
            echo -e "\033[1;31m✗ Lua $VER: FAIL\033[0m"
        fi
    else
        echo -e "\n\033[1;33m>> Lua $VER not found, skipping.\033[0m"
    fi
done

echo -e "\nMatrix Test Done."
