#!/bin/bash
docker compose  -f docker-compose-rmit-poa-no-build.yml down
sleep 1

sudo rm -rf logs  postgres-data  redis-data
sleep 1

docker compose  -f docker-compose-rmit-poa-no-build.yml up -d