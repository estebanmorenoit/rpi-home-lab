#!/bin/bash
set -e

cd /home/esteban/docker-stack

echo "[+] Pulling latest changes..."
git pull origin main

echo "[+] Bringing up Docker stack..."
docker compose -p docker-stack up -d --remove-orphans --no-build

echo "[+] Done."
