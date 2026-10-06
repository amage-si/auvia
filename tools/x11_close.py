#!/usr/bin/env python3
"""Asks an X11/XWayland window to close, as its close button would.

Validation tooling only. Finds top-level windows whose WM_NAME equals the
given title and sends each one a WM_PROTOCOLS / WM_DELETE_WINDOW client
message. Prints the window ids it asked; exit 1 if none matched.

  tools/x11_close.py "Auvia - contador"
"""

import ctypes
import ctypes.util
import sys

x = ctypes.cdll.LoadLibrary(ctypes.util.find_library("X11"))
x.XOpenDisplay.restype = ctypes.c_void_p
x.XOpenDisplay.argtypes = [ctypes.c_char_p]
x.XDefaultRootWindow.restype = ctypes.c_ulong
x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
x.XInternAtom.restype = ctypes.c_ulong
x.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
x.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong),
                         ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),
                         ctypes.POINTER(ctypes.c_uint)]
x.XFetchName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_char_p)]
x.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_long, ctypes.c_void_p]
x.XFlush.argtypes = [ctypes.c_void_p]
x.XFree.argtypes = [ctypes.c_void_p]
x.XCloseDisplay.argtypes = [ctypes.c_void_p]


class ClientMessage(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int),
                ("display", ctypes.c_void_p), ("window", ctypes.c_ulong), ("message_type", ctypes.c_ulong),
                ("format", ctypes.c_int), ("l", ctypes.c_long * 5)]


class Event(ctypes.Union):
    _fields_ = [("xclient", ClientMessage), ("pad", ctypes.c_long * 24)]


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


def main():
    title = sys.argv[1].encode()
    dpy = x.XOpenDisplay(None)
    if not dpy:
        print("no X display")
        return 1
    protocols = x.XInternAtom(dpy, b"WM_PROTOCOLS", 0)
    delete = x.XInternAtom(dpy, b"WM_DELETE_WINDOW", 0)
    asked = []
    for w in windows(dpy, x.XDefaultRootWindow(dpy)):
        name = ctypes.c_char_p()
        if x.XFetchName(dpy, w, ctypes.byref(name)) and name.value == title:
            ev = Event()
            ev.xclient.type = 33  # ClientMessage
            ev.xclient.window = w
            ev.xclient.message_type = protocols
            ev.xclient.format = 32
            ev.xclient.l[0] = delete
            x.XSendEvent(dpy, w, 0, 0, ctypes.byref(ev))
            asked.append(hex(w))
        if name:
            x.XFree(name)
    x.XFlush(dpy)
    x.XCloseDisplay(dpy)
    print("asked to close:", asked)
    return 0 if asked else 1


if __name__ == "__main__":
    sys.exit(main())
