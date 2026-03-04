FROM openresty/openresty:alpine-fat

RUN apk add --no-cache git build-base sqlite-dev openssl-dev mariadb-dev libpq-dev bsd-compat-headers m4

# Instala dependências do Rio
RUN luarocks install luasql-mysql MYSQL_INCDIR=/usr/include/mysql
RUN luarocks install luasql-postgres PGSQL_INCDIR=/usr/include/postgresql

WORKDIR /rio
COPY . .
RUN luarocks make rio-0.1.3-1.rockspec

WORKDIR /app
COPY samples/rio_openresty_native/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

# Cria estrutura básica de um app Rio para o teste nativo
RUN mkdir -p app/controllers config db
RUN echo 'return function(app) app:get("/hello", function(ctx) return ctx:json({message = "Hello from Native OpenResty!"}) end) end' > config/routes.lua
RUN echo 'return {}' > config/database.lua
RUN echo 'return {}' > config/middlewares.lua

EXPOSE 80

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
