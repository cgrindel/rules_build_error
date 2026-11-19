#!/usr/bin/env bash
#
# Mimic GCC, which prints paths based on the resolved directory of its own executable

set -euo pipefail

resolved_dir="$(cd -P "$(dirname "$0")" && pwd -P)"
echo "${resolved_dir}/../lib/as: note: printed to stdout"
echo "${resolved_dir}/../lib/ld: warning: cannot find entry symbol _start" >&2
exit 1
