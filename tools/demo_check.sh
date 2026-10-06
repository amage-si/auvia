#!/usr/bin/env bash
# End-to-end check of examples/counter on a real desktop (validation only).
#
# Launches build/counter, waits for its AT-SPI registration and window,
# captures the window, runs tools/atspi_probe.py (tree dump, GrabFocus,
# DoAction), captures again, closes the window with WM_DELETE_WINDOW and
# records the exit status. Evidence goes to build/evidence/counter-<time>/.
# The window is always closed, also on failure.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
title="Auvia - contador"
out="$root/build/evidence/counter-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
sha256sum "$root/build/counter" "$root/examples/counter.bend" > "$out/identity.txt"

"$root/build/counter" --threads 2 --gpu off > "$out/counter.log" 2>&1 &
pid=$!
echo "$pid" > "$out/pid.txt"

cleanup() {
  if kill -0 "$pid" 2>/dev/null; then
    python3 -I "$root/tools/x11_close.py" "$title" >> "$out/close.txt" 2>&1
    for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  fi
  if kill -0 "$pid" 2>/dev/null; then
    echo "still running after WM_DELETE_WINDOW; sending SIGTERM" >> "$out/close.txt"
    kill "$pid"
  fi
  wait "$pid"
  echo "exit=$?" > "$out/exit.txt"
}
trap cleanup EXIT

for _ in $(seq 1 100); do
  grep -q "counter ready" "$out/counter.log" 2>/dev/null && break
  sleep 0.1
done
sleep 1.5

geometry() {
  hyprctl clients -j | python3 -I -c '
import json, sys
for c in json.load(sys.stdin):
    if c["title"] == sys.argv[1] and c["pid"] == int(sys.argv[2]):
        print("%d,%d %dx%d" % (c["at"][0], c["at"][1], c["size"][0], c["size"][1]))
        break' "$title" "$pid"
}
hyprctl clients -j | python3 -I -c '
import json, sys
print(json.dumps([c for c in json.load(sys.stdin) if c["pid"] == int(sys.argv[1])], indent=2))' "$pid" > "$out/window.json"
geo="$(geometry)"
echo "geometry: $geo"
[ -n "$geo" ] && grim -g "$geo" "$out/01-before.png"

python3 -I -W ignore::DeprecationWarning "$root/tools/atspi_probe.py" --app auvia-counter --x11-title "$title" \
  --button "Clique aqui" --label-prefix "Cliques:" --out "$out/probe.json" | tee "$out/probe.txt"
probe=${PIPESTATUS[0]}

# A second independent client: GLib's gdbus, straight on the a11y bus.
addr="$(gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus \
  --method org.a11y.Bus.GetAddress | sed -E "s/^\('(.*)',\)$/\1/")"
name="$(grep -o 'live as [^,]*' "$out/counter.log" | head -1 | cut -d' ' -f3)"
{
  echo "# a11y bus: $addr, app: $name"
  for path in root 100 2 3; do
    p="/org/a11y/atspi/accessible/$path"
    echo "## $p"
    gdbus call --address "$addr" --dest "$name" --object-path "$p" \
      --method org.freedesktop.DBus.Properties.GetAll org.a11y.atspi.Accessible
    gdbus call --address "$addr" --dest "$name" --object-path "$p" --method org.a11y.atspi.Accessible.GetRoleName
    gdbus call --address "$addr" --dest "$name" --object-path "$p" --method org.a11y.atspi.Accessible.GetState
    gdbus call --address "$addr" --dest "$name" --object-path "$p" --method org.a11y.atspi.Accessible.GetInterfaces
  done
  echo "## introspection of /org/a11y/atspi/accessible/2"
  gdbus introspect --address "$addr" --dest "$name" --object-path /org/a11y/atspi/accessible/2
} > "$out/gdbus.txt" 2>&1
sleep 0.5
geo="$(geometry)"
[ -n "$geo" ] && grim -g "$geo" "$out/02-after-atspi.png"
echo "probe=$probe" > "$out/probe-status.txt"
echo "evidence: $out"
exit "$probe"
