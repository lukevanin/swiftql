#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd -P)"
exec python3 "$script_directory/verify-source-coverage-reproducibility.py" "$@"
