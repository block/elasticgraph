#!/usr/bin/env bash

# Inspired by an example from the docker docs:
# https://docs.docker.com/compose/startup-order/

set -e

host="$1"
shift

until curl -f "$host"; do
  >&2 echo "The datastore is unavailable - sleeping"
  sleep 1
done

>&2 echo "The datastore is up - executing command"
exec "$@"
