#!/usr/bin/env python3
"""Independent AT-SPI check of an Auvia app, through the system's libatspi.

Validation tooling only: it reads the app the way an assistive technology
does and records what it sees. It is not part of Auvia.

  tools/atspi_probe.py --app auvia-counter --button "Clique aqui" \
      --label-prefix "Cliques:" --out build/evidence/probe.json

Steps: find the app under the desktop, dump its tree, subscribe to focus,
state, name, children and text events, GrabFocus the button, invoke its
action through AT-SPI (DoAction), and check the counter label changed
exactly once. With --field, also read the text field's text, caret and
extents through Text, edit it through EditableText (insert, delete, a
refused "☕"), move its caret and select (--field-seed first sets an empty
field's text through SetTextContents). --label-prefix may list several
prefixes separated by "|" (a status line whose wording changes); the
counter is the label's first integer, 0 when it has none. Exit status 0
only when every check passes.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi, GLib  # noqa: E402


def pump(seconds):
    """Runs the GLib main loop so libatspi delivers queued events."""
    loop = GLib.MainLoop()
    GLib.timeout_add(int(seconds * 1000), loop.quit)
    loop.run()


def find_app(name, timeout):
    end = time.time() + timeout
    while time.time() < end:
        desktop = Atspi.get_desktop(0)
        for i in range(desktop.get_child_count()):
            app = desktop.get_child_at_index(i)
            if app is not None and app.get_name() == name:
                return app
        time.sleep(0.25)
    return None


def states(acc):
    return sorted(Atspi.StateType(s).value_nick for s in acc.get_state_set().get_states())


def node(acc, depth=0):
    info = {
        "name": acc.get_name(),
        "role": acc.get_role_name(),
        "role_code": int(acc.get_role()),
        "description": acc.get_description(),
        "states": states(acc),
        "interfaces": sorted(acc.get_interfaces()),
        "index_in_parent": acc.get_index_in_parent(),
        "attributes": acc.get_attributes() or {},
        "accessible_id": acc.get_accessible_id(),
    }
    if "Component" in info["interfaces"]:
        e = acc.get_extents(Atspi.CoordType.WINDOW)
        info["extents_window"] = [e.x, e.y, e.width, e.height]
    if "Action" in info["interfaces"]:
        info["actions"] = [
            {
                "name": acc.get_action_name(i),
                "description": acc.get_action_description(i),
                "key": acc.get_key_binding(i),
            }
            for i in range(acc.get_n_actions())
        ]
    rels = []
    for r in acc.get_relation_set() or []:
        rels.append({
            "type": r.get_relation_type().value_nick,
            "targets": [r.get_target(i).get_name() for i in range(r.get_n_targets())],
        })
    info["relations"] = rels
    info["children"] = [node(acc.get_child_at_index(i), depth + 1) for i in range(acc.get_child_count())]
    return info


def walk(acc):
    yield acc
    for i in range(acc.get_child_count()):
        yield from walk(acc.get_child_at_index(i))


def text_of(acc):
    return Atspi.Text.get_text(acc, 0, -1)


def probe_field(app, args, result, check, pump):
    """Reads and edits a text field the way a screen reader and an
    on-screen keyboard do: Text for reading, EditableText for editing."""
    field = None
    for acc in walk(app):
        if acc.get_role() == Atspi.Role.ENTRY and acc.get_name() == args.field:
            field = acc
    check("field present with entry role", field is not None, args.field)
    if field is None:
        return
    ifaces = sorted(field.get_interfaces())
    fstates = states(field)
    check("field implements Text and EditableText", "Text" in ifaces and "EditableText" in ifaces, ifaces)
    check("field is editable, single-line, focusable and enabled",
          all(s in fstates for s in ("editable", "single-line", "focusable", "enabled")), fstates)

    def events(mark, kind):
        return [e for e in result["events"][mark:] if e["type"].startswith(kind) and e["source"] == args.field]

    # A screen reader follows focus: the field takes it as Tab would.
    if args.field_seed:
        mark = len(result["events"])
        ok = Atspi.EditableText.set_text_contents(field, args.field_seed)
        pump(0.5)
        check("SetTextContents through AT-SPI is performed, visible and announced",
              ok and text_of(field) == args.field_seed and events(mark, "object:text-changed:insert"),
              {"ok": ok, "text": text_of(field), "events": events(mark, "object:text-changed")})

    mark = len(result["events"])
    ok = field.grab_focus()
    pump(1.0)
    check("GrabFocus on the field moves focus there and is announced",
          ok and "focused" in states(field) and events(mark, "focus:") and events(mark, "object:state-changed:focused"),
          {"ok": ok, "states": states(field)})

    text = text_of(field)
    n = Atspi.Text.get_character_count(field)
    caret = Atspi.Text.get_caret_offset(field)
    word = Atspi.Text.get_string_at_offset(field, 0, Atspi.TextGranularity.WORD)
    check("text, count, caret and word read through Text",
          len(text) == n and caret == n and n > 0 and word.content == text.split(" ")[0] and word.start_offset == 0,
          {"text": text, "count": n, "caret": caret, "word": [word.content, word.start_offset, word.end_offset]})
    box = field.get_extents(Atspi.CoordType.WINDOW)
    first = Atspi.Text.get_character_extents(field, 0, Atspi.CoordType.WINDOW)
    whole = Atspi.Text.get_range_extents(field, 0, n, Atspi.CoordType.WINDOW)
    inside = (box.x <= first.x and first.x + first.width <= box.x + box.width and first.width > 0 and first.height > 0
              and box.y <= first.y and first.y + first.height <= box.y + box.height
              and whole.x == first.x and whole.width >= first.width)
    check("character and range extents lie inside the field", inside,
          {"field": [box.x, box.y, box.width, box.height], "char0": [first.x, first.y, first.width, first.height],
           "range": [whole.x, whole.y, whole.width, whole.height]})
    result["field"] = {"text": text, "extents": [box.x, box.y, box.width, box.height],
                       "char0": [first.x, first.y, first.width, first.height]}

    mark = len(result["events"])
    t0 = time.time()
    ok = Atspi.EditableText.insert_text(field, n, " mundo", len(" mundo".encode()))
    took = round(time.time() - t0, 3)
    after = text_of(field)
    pump(0.5)
    inserted = events(mark, "object:text-changed:insert")
    check("InsertText through AT-SPI is performed, visible and announced",
          ok and after == text + " mundo" and len(inserted) == 1 and inserted[0]["detail1"] == n
          and inserted[0]["detail2"] == 6 and events(mark, "object:text-caret-moved"),
          {"ok": ok, "seconds": took, "text": after, "events": inserted})

    mark = len(result["events"])
    ok = Atspi.EditableText.delete_text(field, 0, n + 1)
    after = text_of(field)
    pump(0.5)
    deleted = events(mark, "object:text-changed:delete")
    check("DeleteText through AT-SPI is performed, visible and announced",
          ok and after == "mundo" and len(deleted) == 1 and deleted[0]["detail1"] == 0 and deleted[0]["detail2"] == n + 1,
          {"ok": ok, "text": after, "events": deleted})

    mark = len(result["events"])
    before = text_of(field)
    ok = Atspi.EditableText.insert_text(field, 0, "\u2615", 3)
    after = text_of(field)
    pump(0.5)
    check("a refused InsertText (U+2615, not in the font) reports failure and changes nothing",
          ok is False and after == before and not events(mark, "object:text-changed"),
          {"ok": ok, "before": before, "after": after})

    mark = len(result["events"])
    ok = Atspi.Text.set_caret_offset(field, 2)
    pump(0.5)
    moved = events(mark, "object:text-caret-moved")
    check("SetCaretOffset moves the caret and is announced",
          ok and Atspi.Text.get_caret_offset(field) == 2 and moved and moved[-1]["detail1"] == 2,
          {"ok": ok, "caret": Atspi.Text.get_caret_offset(field), "events": moved})

    mark = len(result["events"])
    ok = Atspi.Text.set_selection(field, 0, 1, 4)
    pump(0.5)
    sel = Atspi.Text.get_selection(field, 0)
    check("SetSelection selects and is announced",
          ok and Atspi.Text.get_n_selections(field) == 1 and (sel.start_offset, sel.end_offset) == (1, 4)
          and events(mark, "object:text-selection-changed"),
          {"ok": ok, "selection": [sel.start_offset, sel.end_offset]})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True)
    ap.add_argument("--button", required=True)
    ap.add_argument("--label-prefix", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--timeout", type=float, default=15.0)
    ap.add_argument("--x11-title", help="also drive the window with X11 input sent only to it")
    ap.add_argument("--outside", default="440,300", help="a window point outside every control")
    ap.add_argument("--field", help="name of an editable text field to read and edit through AT-SPI")
    ap.add_argument("--field-seed", help="text to set (SetTextContents) before reading the field")
    args = ap.parse_args()

    result = {"checks": [], "events": []}
    prefixes = tuple(args.label_prefix.split("|"))

    def check(name, ok, detail=None):
        result["checks"].append({"name": name, "ok": bool(ok), "detail": detail})
        print(("PASS" if ok else "FAIL") + ": " + name + ("" if detail is None else " -- " + str(detail)))

    t0 = time.time()

    def on_event(ev):
        src = ev.source
        result["events"].append({
            "t": round(time.time() - t0, 3),
            "type": ev.type,
            "source": src.get_name() if src is not None else None,
            "source_role": src.get_role_name() if src is not None else None,
            "detail1": ev.detail1,
            "detail2": ev.detail2,
            "any_data": str(ev.any_data) if ev.any_data is not None else None,
        })

    listener = Atspi.EventListener.new(on_event)
    for kind in ("object:state-changed", "object:property-change:accessible-name",
                 "object:children-changed", "focus:", "object:text-changed",
                 "object:text-caret-moved", "object:text-selection-changed"):
        listener.register(kind)

    app = find_app(args.app, args.timeout)
    check("app is listed under the desktop", app is not None, args.app)
    if app is None:
        json.dump(result, open(args.out, "w"), indent=2, ensure_ascii=False)
        return 1

    result["tree"] = node(app)
    check("root role is application", app.get_role() == Atspi.Role.APPLICATION, app.get_role_name())
    tk = app.get_toolkit_name() if hasattr(app, "get_toolkit_name") else None
    result["toolkit"] = tk
    check("toolkit name is Auvia", tk == "Auvia", tk)

    button = label = frame = None
    for acc in walk(app):
        role = acc.get_role()
        if role == Atspi.Role.FRAME:
            frame = acc
        elif role == Atspi.Role.PUSH_BUTTON and acc.get_name() == args.button:
            button = acc
        elif role == Atspi.Role.LABEL and (acc.get_name() or "").startswith(prefixes):
            label = acc
    check("frame present", frame is not None, frame.get_name() if frame else None)
    check("button present with push-button role", button is not None, args.button)
    check("counter label present", label is not None, label.get_name() if label else None)
    if button is None or label is None:
        json.dump(result, open(args.out, "w"), indent=2, ensure_ascii=False)
        return 1

    bstates = states(button)
    check("button is enabled, sensitive, focusable, visible, showing",
          all(s in bstates for s in ("enabled", "sensitive", "focusable", "visible", "showing")), bstates)
    check("button has one action", button.get_n_actions() == 1,
          [button.get_action_name(i) for i in range(button.get_n_actions())])
    hit = frame.get_accessible_at_point(
        button.get_extents(Atspi.CoordType.WINDOW).x + 2,
        button.get_extents(Atspi.CoordType.WINDOW).y + 2, Atspi.CoordType.WINDOW)
    check("frame hit-test at the button finds it", hit is not None and hit.get_name() == args.button,
          hit.get_name() if hit else None)

    def since(mark, kind, source=None, detail1=None):
        return [e for e in result["events"][mark:]
                if e["type"] == kind and (source is None or e["source"] == source)
                and (detail1 is None or e["detail1"] == detail1)]

    def x11(*argv):
        tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), "x11_input.py")
        subprocess.run([sys.executable, "-I", tool, args.x11_title, *argv], check=True,
                       stdout=subprocess.DEVNULL)

    pump(0.5)
    if args.x11_title:
        # User input, through the window: Kairo moves focus and activates;
        # Auvia must announce both without being asked.
        mark = len(result["events"])
        x11("key", "Tab")
        pump(1.0)
        check("keyboard Tab focus is announced (state-changed:focused=1 and focus:)",
              since(mark, "object:state-changed:focused", args.button, 1) and since(mark, "focus:", args.button),
              since(mark, "object:state-changed:focused"))
        before = label.get_name()
        mark = len(result["events"])
        x11("key", "space")
        pump(1.0)
        named = [e for e in since(mark, "object:property-change:accessible-name")
                 if (e["source"] or "").startswith(prefixes)]
        check("keyboard Space activation changes the counter once and is announced once",
              len(named) == 1 and label.get_name() != before, {"before": before, "after": label.get_name(), "events": named})
        mark = len(result["events"])
        ox, oy = args.outside.split(",")
        x11("click", ox, oy)
        pump(1.0)
        check("click outside the button announces focus loss (focused=0)",
              since(mark, "object:state-changed:focused", args.button, 0) and "focused" not in states(button),
              since(mark, "object:state-changed:focused"))

    before = label.get_name()
    mark = len(result["events"])

    ok = button.grab_focus()
    pump(1.0)
    focus_events = [e for e in result["events"][mark:]
                    if (e["type"] == "object:state-changed:focused" and e["detail1"] == 1
                        and e["source"] == args.button) or
                    (e["type"].startswith("focus") and e["source"] == args.button)]
    check("GrabFocus accepted", ok)
    check("focus event announced for the button", len(focus_events) > 0, focus_events)
    check("button now reports focused", "focused" in states(button), states(button))

    mark = len(result["events"])
    done = button.do_action(0)
    pump(1.5)
    after = label.get_name()
    name_events = [e for e in result["events"][mark:]
                   if e["type"] == "object:property-change:accessible-name"
                   and (e["source"] or "").startswith(prefixes)]
    check("DoAction(0) accepted", done)
    def count(name):
        m = re.search(r"\d+", name or "")
        return int(m.group()) if m else 0
    n0, n1 = count(before), count(after)
    check("counter incremented exactly once through AT-SPI", n0 is not None and n1 == n0 + 1,
          {"before": before, "after": after})
    check("name change announced exactly once", len(name_events) == 1, name_events)

    if args.field:
        probe_field(app, args, result, check, pump)

    result["elapsed_s"] = round(time.time() - t0, 3)
    with open(args.out, "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    failed = [c for c in result["checks"] if not c["ok"]]
    print(("ALL CHECKS PASSED" if not failed else str(len(failed)) + " CHECK(S) FAILED") +
          " (" + str(len(result["checks"])) + " checks)")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
