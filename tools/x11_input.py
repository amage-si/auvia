#!/usr/bin/env python3
"""Sends key presses or a click to one X11/XWayland window (validation only).

Events go only to the window whose WM_NAME matches, with XSendEvent and no
propagation; nothing is injected globally.

  tools/x11_input.py "Auvia - contador" key Tab
  tools/x11_input.py "Auvia - contador" key space
  tools/x11_input.py "Auvia - contador" click 400 280
  tools/x11_input.py "Auvia - contador" focus in      (or: focus out)

`focus` sends a FocusIn/FocusOut event (mode Normal, detail Nonlinear), as
the server does when the window manager moves keyboard focus; the real
keyboard focus of the desktop does not change.
"""

import ctypes
import ctypes.util
import sys
import time

x = ctypes.cdll.LoadLibrary(ctypes.util.find_library("X11"))
x.XOpenDisplay.restype = ctypes.c_void_p
x.XOpenDisplay.argtypes = [ctypes.c_char_p]
x.XDefaultRootWindow.restype = ctypes.c_ulong
x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
x.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong),
                         ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),
                         ctypes.POINTER(ctypes.c_uint)]
x.XFetchName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_char_p)]
x.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_long, ctypes.c_void_p]
x.XFlush.argtypes = [ctypes.c_void_p]
x.XFree.argtypes = [ctypes.c_void_p]
x.XCloseDisplay.argtypes = [ctypes.c_void_p]
x.XStringToKeysym.restype = ctypes.c_ulong
x.XStringToKeysym.argtypes = [ctypes.c_char_p]
x.XKeysymToKeycode.restype = ctypes.c_ubyte
x.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]


class KeyEvent(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int),
                ("display", ctypes.c_void_p), ("window", ctypes.c_ulong), ("root", ctypes.c_ulong),
                ("subwindow", ctypes.c_ulong), ("time", ctypes.c_ulong), ("x", ctypes.c_int), ("y", ctypes.c_int),
                ("x_root", ctypes.c_int), ("y_root", ctypes.c_int), ("state", ctypes.c_uint),
                ("code", ctypes.c_uint), ("same_screen", ctypes.c_int)]


class FocusEvent(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int),
                ("display", ctypes.c_void_p), ("window", ctypes.c_ulong), ("mode", ctypes.c_int),
                ("detail", ctypes.c_int)]


class Event(ctypes.Union):
    _fields_ = [("xkey", KeyEvent), ("xfocus", FocusEvent), ("pad", ctypes.c_long * 24)]


def windows(dpy, w):
    root = ctypes.c_ulong()
    parent = ctypes.c_ulong()
    kids = ctypes.POINTER(ctypes.c_ulong)()
    n = ctypes.c_uint()
    if not x.XQueryTree(dpy, w, ctypes.byref(root), ctypes.byref(parent), ctypes.byref(kids), ctypes.byref(n)):
        return
    found = [kids[i] for i in range(n.value)]
    if kids:
        x.XFree(kids)
    for k in found:
        yield k
        yield from windows(dpy, k)


def find(dpy, title):
    for w in windows(dpy, x.XDefaultRootWindow(dpy)):
        name = ctypes.c_char_p()
        hit = x.XFetchName(dpy, w, ctypes.byref(name)) and name.value == title
        if name:
            x.XFree(name)
        if hit:
            return w
    return None


def send(dpy, w, kind, code, px=0, py=0, mask=0):
    ev = Event()
    ev.xkey.type = kind
    ev.xkey.send_event = 1
    ev.xkey.display = dpy
    ev.xkey.window = w
    ev.xkey.root = x.XDefaultRootWindow(dpy)
    ev.xkey.x = px
    ev.xkey.y = py
    ev.xkey.code = code
    ev.xkey.same_screen = 1
    x.XSendEvent(dpy, w, 0, mask, ctypes.byref(ev))
    x.XFlush(dpy)


def main():
    title = sys.argv[1].encode()
    dpy = x.XOpenDisplay(None)
    w = find(dpy, title)
    if w is None:
        print("window not found")
        return 1
    if sys.argv[2] == "key":
        code = x.XKeysymToKeycode(dpy, x.XStringToKeysym(sys.argv[3].encode()))
        send(dpy, w, 2, code, mask=1)       # KeyPress, KeyPressMask
        time.sleep(0.08)
        send(dpy, w, 3, code, mask=2)       # KeyRelease, KeyReleaseMask
    elif sys.argv[2] == "focus":
        ev = Event()
        ev.xfocus.type = 9 if sys.argv[3] == "in" else 10   # FocusIn / FocusOut
        ev.xfocus.send_event = 1
        ev.xfocus.display = dpy
        ev.xfocus.window = w
        ev.xfocus.mode = 0                                    # NotifyNormal
        ev.xfocus.detail = 3                                  # NotifyNonlinear
        x.XSendEvent(dpy, w, 0, 1 << 21, ctypes.byref(ev))    # FocusChangeMask
        x.XFlush(dpy)
    elif sys.argv[2] == "click":
        px, py = int(sys.argv[3]), int(sys.argv[4])
        send(dpy, w, 6, 0, px, py, mask=64)  # MotionNotify, PointerMotionMask
        send(dpy, w, 4, 1, px, py, mask=4)   # ButtonPress button 1
        time.sleep(0.08)
        send(dpy, w, 5, 1, px, py, mask=8)   # ButtonRelease button 1
    x.XCloseDisplay(dpy)
    print("sent", sys.argv[2:], "to", hex(w))
    return 0


if __name__ == "__main__":
    sys.exit(main())
