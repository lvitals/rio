FROM openresty/openresty:alpine-fat

# Install build dependencies
RUN apk add --no-cache git build-base sqlite-dev openssl-dev mariadb-dev libpq-dev bsd-compat-headers m4 lua5.1 lua5.1-dev

# 1. Pre-install dependencies that require custom paths
RUN luarocks install luasql-mysql MYSQL_INCDIR=/usr/include/mysql --tree /usr/local
RUN luarocks install luasql-postgres PGSQL_INCDIR=/usr/include/postgresql --tree /usr/local

# 2. Install Rio framework from LuaRocks
RUN luarocks install rio --tree /usr/local

# Setup application
WORKDIR /app
COPY samples/rio_showcase_mvc .

# Set Lua environment variables
ENV LUA_PATH="/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;./?.lua;./app/?.lua;./app/?/init.lua;;"
ENV LUA_CPATH="/usr/local/lib/lua/5.1/?.so;;"
ENV PATH="/usr/local/bin:${PATH}"

EXPOSE 8080

# Run migrations and start the server
CMD rio db:migrate && rio server
