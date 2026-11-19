set -euo pipefail

usage() {
    cat <<EOS >&2
Try building the code.

With the option '-f', this script can receive arbitrary number of files.
If any of them is an empty file, this script exits successfully
without executing the build command.

Even if the build command fails, this script won't exit with an error.

Note that this script is supposed to be invoked by 'ctx.actions.run_shell'.
Usage: bash -c '\$@' '' $0 [OPTIONS] COMMAND

OPTIONS
    -f FILE_TO_CHECK
        Successfully exit if the file is empty
    -h
        Show usage and exit
    -e STDOUT_FILE
        A file path to write stderr message
    -o STDOUT_FILE
        A file path to write stdout message
    -n NEW_FILE_PATH
        If specified, create a new empty file with 'touch' before exiting the script.

COMMAND
    Build command.
    Executed if there's no empty file given with '-f'.
EOS
}

exit_if_containing_an_empty_file() {
    # Exit if the arguments contains an empty file
    #
    # Args:
    #   $@: file paths
    local file_paths
    local file_path
    file_paths=("$@")

    for file_path in "${file_paths[@]}"; do
        if [[ ! -f "${file_path}" ]]; then
            echo "ERROR: ${file_path} does not exist" >&2
            exit 1
        fi
    done

    for file_path in "${file_paths[@]}"; do
        if [[ ! -s "${file_path}" ]]; then
            # File is empty: exit successfully
            exit 0
        fi
    done
}

unresolve_tool_dir() {
    # Rewrite the build tool's resolved directory to the directory it was invoked from
    #
    # GCC finds its sub-tools (e.g. 'ld') from the resolved, absolute path of its own
    # executable and prints that path in diagnostics. Bazel invokes the tool by a
    # relative path (e.g. 'external/<repo>/bin/gcc'), and the resolved location of
    # that path differs between machines. Replacing the resolved directory with the
    # invoked one makes the captured output the same on every machine.
    #
    # Args:
    #   $1: build tool path
    #   $2...: files to rewrite
    local tool
    local tool_dir
    local path
    local target
    local hops
    local real_dir
    local output_file
    tool="$1"
    shift

    if [[ "${tool}" != */* || ! -e "${tool}" ]]; then
        return 0
    fi
    tool_dir="$(dirname "${tool}")"

    path="${tool}"
    hops=0
    while [[ -L "${path}" ]]; do
        hops=$((hops + 1))
        if [[ "${hops}" -gt 40 ]]; then
            echo "ERROR: too many levels of symbolic links: ${tool}" >&2
            exit 1
        fi
        target="$(readlink "${path}")"
        if [[ "${target}" != /* ]]; then
            target="$(dirname "${path}")/${target}"
        fi
        path="${target}"
    done
    real_dir="$(cd -P "$(dirname "${path}")" && pwd -P)"
    if [[ "${real_dir}" == "${tool_dir}" ]]; then
        return 0
    fi

    for output_file in "$@"; do
        if [[ ! -f "${output_file}" ]]; then
            continue
        fi
        # ENVIRON and index() keep the match literal for any character in the paths
        FROM="${real_dir}/" TO="${tool_dir}/" awk '
            BEGIN { from = ENVIRON["FROM"]; to = ENVIRON["TO"] }
            {
                line = $0
                out = ""
                while ((i = index(line, from)) > 0) {
                    out = out substr(line, 1, i - 1) to
                    line = substr(line, i + length(from))
                }
                print out line
            }
        ' "${output_file}" >"${output_file}.tmp"
        mv "${output_file}.tmp" "${output_file}"
    done
}

files_to_check=()
files_to_touch=()
stdout_file="/dev/null"
stderr_file="/dev/null"

while getopts "e:f:hn:o:" opt; do
    case "${opt}" in
        e)
            stderr_file="${OPTARG}"
        ;;
        f)
            files_to_check+=("${OPTARG}")
        ;;
        h)
            usage
            exit 0
        ;;
        n)
            files_to_touch+=("${OPTARG}")
        ;;
        o)
            stdout_file="${OPTARG}"
        ;;
    esac
done
shift $((OPTIND -1))

# Make sure the required files are touched before exiting
if [[ "${#files_to_touch[@]}" -gt 0 ]]; then
    trap 'for file_to_touch in "${files_to_touch[@]}"; do [[ ! -f "${file_to_touch}" ]] && > "${file_to_touch}"; done' EXIT
fi

if [[ "${#files_to_check[@]}" -gt 0 ]]; then
    exit_if_containing_an_empty_file "${files_to_check[@]}"
fi

"$@" >"${stdout_file}" 2>"${stderr_file}" || true
unresolve_tool_dir "$1" "${stdout_file}" "${stderr_file}"
