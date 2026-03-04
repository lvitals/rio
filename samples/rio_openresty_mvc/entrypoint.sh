#!/bin/sh

# entrypoint.sh - Configures database and starts OpenResty

echo "--- Dropping Database ---"
rio db:drop

echo "--- Running Migrations ---"
rio db:migrate

echo "--- Running Seeds ---"
rio db:seed

echo "--- Starting OpenResty ---"
exec "$@"
