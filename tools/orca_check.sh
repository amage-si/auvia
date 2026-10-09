#!/usr/bin/env bash
# Runs an Auvia example under the Orca screen reader and records what Orca
# says (validation only).
#
#   tools/orca_check.sh          examples/counter in its window, driven by
#                                X11 input sent only to that window
#   tools/orca_check.sh field    examples/headless (no window), driven by
#                                tools/atspi_probe.py --field: focus on the
#                                button and the field, AT-SPI edits
#   tools/orca_check.sh eco      Chromi's integrated demo (../Chromi/build/eco),
#                                opened on a silent workspace without focus;
#                                input sent only to its window (synthetic
#                                FocusIn before each step, Tab, Space, typing),
#                                then the probe on the field
#   tools/orca_check.sh eco-typed  the same demo, typed with real keys (XTest):
#                                it focuses the demo window, types, and gives
#                                focus back. Only with the desktop's owner
#                                away from the keyboard and mouse.
#
# Orca gets character and word echo on (throwaway settings migrated from a
# user-settings.conf), so typed characters and words are spoken when Orca
# sees them typed.
#
# Isolation: Orca gets in-memory GSettings and throwaway XDG dirs, so the
# user's Orca settings are neither read nor written. Speech goes to a private
# speech-dispatcher on its own socket, with OSS output (no device here) and
# volume -100: Orca's debug log records every utterance, nothing is heard.
# Everything started here is stopped at the end. Evidence goes to
# build/evidence/orca-<time>/: speech.txt, the extracted "SPEECH OUTPUT"
# lines. Orca hears the whole desktop, so its debug log (kept as orca.out
# only with KEEP_ORCA_LOG=1) and even speech.txt can hold text from other
# applications: review them, redact them to the app's lines, delete them.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:-counter}"
title="Auvia - contador"
out="$root/build/evidence/orca-$mode-$(date +%Y%m%d-%H%M%S)"
tmp="$(mktemp -d /tmp/auvia-orca.XXXXXX)"
mkdir -p "$out" "$tmp/config" "$tmp/data/orca" "$tmp/cache"
printf '{"profiles": {"default": {"profile": ["Default", "default"], "enableEchoByCharacter": true, "enableEchoByWord": true}}}\n' \
  > "$tmp/data/orca/user-settings.conf"
eco_title="AMAGE Eco - Ankra, Voltra, Chromi"

cp -r /etc/speech-dispatcher "$tmp/speechd"
sed -i 's/^DefaultVolume 100/DefaultVolume -100/' "$tmp/speechd/speechd.conf"
printf 'AudioOutputMethod "oss"\nDefaultModule espeak-ng\n' >> "$tmp/speechd/speechd.conf"

cleanup() {
  if [ -n "${app:-}" ] && kill -0 "$app" 2>/dev/null; then
    [ "$mode" = counter ] && python3 -I "$root/tools/x11_close.py" "$title" > /dev/null 2>&1
    [ -n "${addr:-}" ] && hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" > /dev/null 2>&1
    for _ in $(seq 1 50); do kill -0 "$app" 2>/dev/null || break; sleep 0.1; done
    kill "$app" 2>/dev/null
  fi
  [ -n "${orca:-}" ] && kill -TERM "$orca" 2>/dev/null
  for _ in $(seq 1 50); do kill -0 "${orca:-0}" 2>/dev/null || break; sleep 0.1; done
  [ -n "${sd:-}" ] && kill -TERM "$sd" 2>/dev/null
  for _ in $(seq 1 50); do kill -0 "${sd:-0}" 2>/dev/null || break; sleep 0.1; done
  [ -n "${sd:-}" ] && kill -KILL "$sd" 2>/dev/null
  pkill -KILL -f "$tmp/speechd" 2>/dev/null
  grep "SPEECH OUTPUT" "$tmp/orca.out" | sed -E "s/ \{.*$//" > "$out/speech.txt"
  [ "${KEEP_ORCA_LOG:-0}" = 1 ] && cp "$tmp/orca.out" "$out/orca.out"
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

# Sends one key (keysym name) or a FocusIn only to the eco demo's window.
eco_key() { python3 -I "$root/tools/x11_input.py" "$eco_title" "$@" > /dev/null; }

if [ "$mode" = eco ] || [ "$mode" = eco-typed ]; then
  run="$tmp/eco.sh"
  printf '#!/bin/bash\ncd %q\nenv -u WAYLAND_DISPLAY ./build/eco --threads 2 --gpu off > %q 2>&1\n' \
    "$root/../Chromi" "$out/eco.log" > "$run"
  chmod +x "$run"
  hyprctl dispatch "hl.dsp.exec_cmd('$run', { workspace = '1 silent', float = true, no_initial_focus = true, no_anim = true })" > /dev/null
  for _ in $(seq 1 100); do
    addr=$(hyprctl clients -j | python3 -I -c "
import json,sys
print(next((c['address'] for c in json.load(sys.stdin) if c['title'] == sys.argv[1]), ''))" "$eco_title")
    [ -n "$addr" ] && break; sleep 0.1
  done
  app=$(pgrep -n -f "[.]/build/eco --threads")
  sleep 3
  if [ "$mode" = eco ]; then
    for step in "key Tab" "key space" "key Tab" "key o" "key l" "key dead_acute" "key a" "key space" "key m" "key u" "key n" "key d" "key o"; do
      echo "$(date +%T.%N) $step" >> "$out/input.txt"
      eco_key focus in; sleep 0.3; eco_key $step; sleep 1.5
    done
  else
    prev=$(hyprctl activewindow -j | python3 -I -c "import json,sys; print(json.load(sys.stdin).get('address', ''))")
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" > /dev/null
    sleep 1
    for step in Tab space Tab o l dead_acute a space m u n d o space; do
      now=$(hyprctl activewindow -j | python3 -I -c "import json,sys; print(json.load(sys.stdin).get('address', ''))")
      [ "$now" = "$addr" ] || { echo "$(date +%T.%N) focus moved away; stopped" >> "$out/input.txt"; break; }
      echo "$(date +%T.%N) key $step" >> "$out/input.txt"
      xdotool key "$step"; sleep 1.5
    done
    [ -n "$prev" ] && hyprctl dispatch "hl.dsp.focus({ window = \"address:$prev\" })" > /dev/null
  fi
  echo "$(date +%T.%N) probe" >> "$out/input.txt"
  python3 -I -W ignore::DeprecationWarning "$root/tools/atspi_probe.py" --app amage-eco --button Ativar \
    --label-prefix "Clique no botão|Ativado" --field "Texto livre" --out "$out/probe.json" > "$out/probe.txt" 2>&1
  sleep 2
elif [ "$mode" = field ]; then
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
