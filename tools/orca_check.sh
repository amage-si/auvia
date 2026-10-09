#!/usr/bin/env bash
# Runs an Auvia example under the Orca screen reader and records what Orca
# says (validation only).
#
#   tools/orca_check.sh          examples/counter in its window, driven by
#                                X11 input sent only to that window
#   tools/orca_check.sh field    examples/headless (no window), driven by
#                                tools/atspi_probe.py --field: focus on the
#                                button and the field, AT-SPI edits
#
# Isolation: Orca gets in-memory GSettings and throwaway XDG dirs, so the
# user's Orca settings are neither read nor written. Speech goes to a private
# speech-dispatcher on its own socket, with OSS output (no device here) and
# volume -100: Orca's debug log records every utterance, nothing is heard.
# Everything started here is stopped at the end. Evidence goes to
# build/evidence/orca-<time>/ (orca.out is Orca's debug log; speech.txt the
# extracted "SPEECH OUTPUT" lines).
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-counter}"
title="Auvia - contador"
out="$root/build/evidence/orca-$mode-$(date +%Y%m%d-%H%M%S)"
tmp="$(mktemp -d /tmp/auvia-orca.XXXXXX)"
mkdir -p "$out" "$tmp/config" "$tmp/data" "$tmp/cache"

cp -r /etc/speech-dispatcher "$tmp/speechd"
sed -i 's/^DefaultVolume 100/DefaultVolume -100/' "$tmp/speechd/speechd.conf"
printf 'AudioOutputMethod "oss"\nDefaultModule espeak-ng\n' >> "$tmp/speechd/speechd.conf"

cleanup() {
  if [ -n "${app:-}" ] && kill -0 "$app" 2>/dev/null; then
    [ "$mode" = counter ] && python3 -I "$root/tools/x11_close.py" "$title" > /dev/null 2>&1
    for _ in $(seq 1 50); do kill -0 "$app" 2>/dev/null || break; sleep 0.1; done
    kill "$app" 2>/dev/null
  fi
  [ -n "${orca:-}" ] && kill -TERM "$orca" 2>/dev/null
  for _ in $(seq 1 50); do kill -0 "${orca:-0}" 2>/dev/null || break; sleep 0.1; done
  [ -n "${sd:-}" ] && kill -TERM "$sd" 2>/dev/null
  for _ in $(seq 1 50); do kill -0 "${sd:-0}" 2>/dev/null || break; sleep 0.1; done
  [ -n "${sd:-}" ] && kill -KILL "$sd" 2>/dev/null
  pkill -KILL -f "$tmp/speechd" 2>/dev/null
  cp "$tmp/orca.out" "$out/orca.out" 2>/dev/null
  grep "SPEECH OUTPUT" "$out/orca.out" | sed -E "s/ \{.*$//" > "$out/speech.txt"
  rm -rf "$tmp"
}
trap cleanup EXIT

speech-dispatcher -s -C "$tmp/speechd" -S "$tmp/speechd.sock" -t 0 -P "$tmp/speechd.pid" -L "$tmp" \
  > "$out/speechd.txt" 2>&1 &
sd=$!
for _ in $(seq 1 50); do [ -S "$tmp/speechd.sock" ] && break; sleep 0.1; done

SPEECHD_ADDRESS="unix_socket:$tmp/speechd.sock" GSETTINGS_BACKEND=memory \
  XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data" XDG_CACHE_HOME="$tmp/cache" \
  orca --replace --debug-file "$tmp/orca.out" > "$out/orca-stdout.txt" 2>&1 &
orca=$!
sleep 4

if [ "$mode" = field ]; then
  "$root/build/headless" --threads 2 --gpu off > "$out/headless.log" 2>&1 &
  app=$!
  for _ in $(seq 1 100); do grep -q "headless: live" "$out/headless.log" 2>/dev/null && break; sleep 0.1; done
  sleep 3
  echo "$(date +%T.%N) probe" >> "$out/input.txt"
  python3 -I -W ignore::DeprecationWarning "$root/tools/atspi_probe.py" --app auvia-headless --button Incrementar \
    --label-prefix "Cliques:" --field Nome --out "$out/probe.json" > "$out/probe.txt" 2>&1
  sleep 2
else
  "$root/build/counter" --threads 2 --gpu off > "$out/counter.log" 2>&1 &
  app=$!
  for _ in $(seq 1 100); do grep -q "counter ready" "$out/counter.log" 2>/dev/null && break; sleep 0.1; done
  sleep 3

  # User input, only to the demo window: Tab, Space, Enter, click away, Tab.
  for step in "key Tab" "key space" "key Return" "click 440 300" "key Tab"; do
    echo "$(date +%T.%N) $step" >> "$out/input.txt"
    python3 -I "$root/tools/x11_input.py" "$title" $step > /dev/null
    sleep 2
  done
fi
sleep 1
echo "evidence: $out"
