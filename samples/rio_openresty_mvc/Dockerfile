FROM openresty/openresty:alpine-fat

# Install system dependencies
RUN apk add --no-cache git build-base sqlite sqlite-dev openssl-dev mariadb-dev libpq-dev bsd-compat-headers m4

# Install Rio dependencies and database drivers
RUN luarocks install luasql-mysql MYSQL_INCDIR=/usr/include/mysql
RUN luarocks install luasql-postgres PGSQL_INCDIR=/usr/include/postgresql
RUN luarocks install luasql-sqlite3
RUN luarocks install rio

# Set application directory
WORKDIR /app
COPY . .

# Copy local nginx.conf to the correct OpenResty location
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

# Create log directory and ensure database permissions
RUN mkdir -p log db && chmod 777 log db

# Ensure database file is writable if it already exists
RUN touch db/development.sqlite3 && chmod 666 db/development.sqlite3

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
