#!/bin/zsh
# Drives a running Lazybones from the terminal: a debug build, or one started with --control.
#
#   Scripts/ctl.sh press down down select  remote buttons, one after another ("press home hold" holds)
#   Scripts/ctl.sh swipe left left         swipes on the touch surface
#   Scripts/ctl.sh open netflix
#   Scripts/ctl.sh eval document.title     JavaScript in the open page (eval @youtube ... for another)
#   Scripts/ctl.sh state                   what's on screen, overlays, pages, remote, TV, volume
#   Scripts/ctl.sh log 100                 the last 100 log lines
#   Scripts/ctl.sh settings | overlay | window | reload
#
# Buttons: up down left right select back home playpause volup voldown mute siri power.
# With several instances running it talks to the newest; LAZYBONES_PID=<pid> picks another.
# Commands go over a distributed notification; the reply comes back through a temporary file.
set -euo pipefail

if (( $# == 0 )) || [[ $1 == (-h|--help|help) ]]; then
    sed -n '2,14s/^# \{0,1\}//p' "$0"
    exit 0
fi
pid=${LAZYBONES_PID:-$(pgrep -xn Lazybones || true)}
if [[ -z $pid ]]; then
    echo "Lazybones isn't running (Scripts/run.sh starts it)" >&2
    exit 1
fi
if [[ -z ${LAZYBONES_PID:-} ]] && (( $(pgrep -x Lazybones | wc -l) > 1 )); then
    echo "(several running: talking to the newest, $pid; LAZYBONES_PID picks another)" >&2
fi

reply=$(mktemp -u "${TMPDIR:-/tmp}/lazybones-ctl.XXXXXX")
trap 'rm -f "$reply"' EXIT

osascript -l JavaScript - "$pid" "$reply" "$@" >/dev/null <<'JS'
ObjC.import('Foundation');
function run(argv) {
  const [pid, reply, ...args] = argv;
  $.NSDistributedNotificationCenter.defaultCenter
    .postNotificationNameObjectUserInfoDeliverImmediately('dev.lull.lazybones.control.' + pid, $(), $({ args, reply }), true);
}
JS

# Long enough for a slow eval; LAZYBONES_CTL_TIMEOUT (seconds) for slower ones.
for _ in {1..$(( ${LAZYBONES_CTL_TIMEOUT:-10} * 20 ))}; do
    if [[ -f $reply ]]; then
        cat "$reply"
        echo
        grep -q '^error:' "$reply" && exit 1
        exit 0
    fi
    sleep 0.05
done
echo "no reply from $pid. Is it a debug build, or was it started with --control?" >&2
exit 1
