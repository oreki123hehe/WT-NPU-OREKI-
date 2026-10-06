#!/bin/sh
# Jalankan seluruh regresi WT-NPU: small -> full -> stress
set -e
cd "$(dirname "$0")/.."
make pe
make small
make test
make stress
echo "=== SEMUA REGRESI SELESAI ==="
