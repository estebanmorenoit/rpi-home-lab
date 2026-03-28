#!/bin/bash
set -e

cd /home/esteban/docker-stack
git pull origin main
docker compose pull
docker compose -p docker-stack up -d --no-build --remove-orphans
