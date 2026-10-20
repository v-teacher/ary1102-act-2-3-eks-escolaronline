#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../app"
docker build --platform linux/amd64 -t ary1102-act23-frontend:validation ./microservicioEKSFrontend
for ACT_SERVICE in get-products create-product update-product delete-product; do
  docker build --platform linux/amd64 -t "ary1102-act23-$ACT_SERVICE:validation" "./microserviciosEKSBackend/$ACT_SERVICE"
done
