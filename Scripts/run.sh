#!/bin/zsh
# Builds Lazybones.app and runs it in this terminal, windowed, with its log echoed here. ^C quits it.
#
#   Scripts/run.sh                          debug build
#   Scripts/run.sh --open youtube --remote  any launch options (Scripts/run.sh --help lists them)
#   Scripts/run.sh --release ...            release build (still takes Scripts/ctl.sh commands)
#
# Debug builds take commands from Scripts/ctl.sh. Pass --fresh-settings to leave your saved
# settings alone.
set -euo pipefail
cd "${0:A:h}/.."

build=(--debug)
extra=()
if [[ "${1:-}" == --release ]]; then
    build=()
    extra=(--control)
    shift
fi
APP=build/Lazybones.app/Contents/MacOS/Lazybones
if [[ "${1:-}" == (--help|-h) ]]; then
    [[ -x $APP ]] || Scripts/build.sh $build
    exec $APP --help
fi

Scripts/build.sh $build
exec $APP --windowed --log $extra "$@"
