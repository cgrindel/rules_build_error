#!/usr/bin/env bash
#
# Check that 'try_build.bash' replaces the resolved directory of the build tool
# with the directory it was invoked from, in both stdout and stderr.
#
# Args:
#   $1: path to 'try_build.bash'
#   $2: path to the fake build tool
#   $3: marker file to create on success

set -euo pipefail

check_content() {
    # Exit with an error if the file content differs from the expected one
    #
    # Args:
    #   $1: file path
    #   $2: expected content
    local file_path
    local expected
    local actual
    file_path="$1"
    expected="$2"
    actual="$(cat "${file_path}")"

    if [[ "${actual}" != "${expected}" ]]; then
        echo "ERROR: unexpected content in ${file_path}" >&2
        echo "Expected: ${expected}" >&2
        echo "Actual:   ${actual}" >&2
        exit 1
    fi
}

try_build="$(pwd)/$1"
fake_tool="$(pwd)/$2"
marker="$(pwd)/$3"
work_dir="${marker}.work"

rm -rf "${work_dir}"
mkdir -p "${work_dir}/real/bin"
cp "${fake_tool}" "${work_dir}/real/bin/gcc"
chmod +x "${work_dir}/real/bin/gcc"
cd "${work_dir}"

# Invoke the tool through a symbolic link, as with an external repository
ln -s real link
bash "${try_build}" -e stderr.txt -o stdout.txt link/bin/gcc

check_content stdout.txt "link/bin/../lib/as: note: printed to stdout"
check_content stderr.txt "link/bin/../lib/ld: warning: cannot find entry symbol _start"

touch "${marker}"
