FROM openresty/openresty:alpine-fat

# Install system dependencies
RUN apk add --no-cache git build-base sqlite sqlite-dev openssl-dev mariadb-dev libpq-dev bsd-compat-headers m4

# Install Rio dependencies
RUN luarocks install luasql-mysql MYSQL_INCDIR=/usr/include/mysql
RUN luarocks install luasql-postgres PGSQL_INCDIR=/usr/include/postgresql
RUN luarocks install luasql-sqlite3
RUN luarocks install http
RUN luarocks install luasocket
RUN luarocks install luaposix
RUN luarocks install lpeg
RUN luarocks install lua-cjson
RUN luarocks install luasec
RUN luarocks install net-url
RUN luarocks install busted
RUN luarocks install linenoise

# 1. First, install the framework from local source
WORKDIR /framework
COPY . .
RUN luarocks make rio-dev-1.rockspec

# 2. Setup the application
WORKDIR /app
COPY samples/rio_openresty_mvc/. .

# Copy custom nginx.conf
COPY samples/rio_openresty_mvc/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

# Ensure logs and DB directories exist
RUN mkdir -p log db && chmod 777 log db && touch db/development.sqlite3 && chmod 666 db/development.sqlite3

RUN chmod +x entrypoint.sh

EXPOSE 80

ENTRYPOINT ["./entrypoint.sh"]
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
