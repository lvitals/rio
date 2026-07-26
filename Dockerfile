FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        lua5.4 \
        lua5.4-dev \
        luarocks \
        libmariadb-dev \
        libmariadb-dev-compat \
        libpq-dev \
        libsqlite3-dev \
        libssl-dev \
        m4 \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --set lua-interpreter /usr/bin/lua5.4 \
    && update-alternatives --set lua-compiler /usr/bin/luac5.4

WORKDIR /app

COPY rio-dev-1.rockspec rio-0.1.21-1.rockspec ./

RUN luarocks --lua-version=5.4 install busted \
    && luarocks --lua-version=5.4 install bestline \
    && luarocks --lua-version=5.4 make rio-dev-1.rockspec --only-deps

RUN git clone --depth 1 --branch master https://github.com/lunarmodules/luasql.git /tmp/luasql \
    && cd /tmp/luasql \
    && luarocks --lua-version=5.4 make rockspec/luasql-postgres-2.8.0-1.rockspec PGSQL_INCDIR=/usr/include/postgresql \
    && luarocks --lua-version=5.4 make rockspec/luasql-mysql-2.8.0-1.rockspec MYSQL_INCDIR=/usr/include/mariadb MYSQL_LIBDIR=/usr/lib/x86_64-linux-gnu \
    && luarocks --lua-version=5.4 make rockspec/luasql-sqlite3-2.8.0-1.rockspec SQLITE_INCDIR=/usr/include SQLITE_LIBDIR=/usr/lib/x86_64-linux-gnu \
    && rm -rf /tmp/luasql

RUN printf '#!/bin/sh\nexec lua5.4 /app/bin/rio "$@"\n' > /usr/local/bin/rio \
    && chmod +x /usr/local/bin/rio

COPY . .

ENV RIO_ENV=test \
    RIO_HASH_ITERATIONS=1 \
    RIO_TEST_POSTGRES_HOST=postgres \
    RIO_TEST_MYSQL_HOST=mysql \
    RIO_TEST_POSTGRES_DB=postgres \
    RIO_TEST_POSTGRES_USER=postgres \
    RIO_TEST_POSTGRES_PASS=postgres \
    RIO_TEST_MYSQL_DB=test \
    RIO_TEST_MYSQL_USER=root \
    RIO_TEST_MYSQL_PASS=123456

CMD ["lua5.4", "./bin/rio", "test"]
