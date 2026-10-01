#!/bin/zsh
# Shows Lazybones's log from the unified log, whether or not it was started with --log.
#
#   Scripts/logs.sh              follow it live
#   Scripts/logs.sh 10m          the last 10 minutes (debug lines aren't kept, so not those)
#   Scripts/logs.sh -c page      one category: app remote web page tv ext audio control
#   Scripts/logs.sh -c web 1h
set -euo pipefail

predicate='subsystem == "dev.lull.lazybones" AND process == "Lazybones"'
last=
while (( $# )); do
    case $1 in
        -c|--category) predicate+=" AND category == \"$2\""; shift 2 ;;
        -h|--help) sed -n '2,8s/^# \{0,1\}//p' "$0"; exit 0 ;;
        *) last=$1; shift ;;
    esac
done

if [[ -n $last ]]; then
    exec /usr/bin/log show --last "$last" --info --style compact --predicate "$predicate"
else
    exec /usr/bin/log stream --level debug --style compact --predicate "$predicate"
fi
