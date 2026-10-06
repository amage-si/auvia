// Auvia native bridge: Unix.connect (JS lane, Linux)
// Builds a sockaddr_un by hand: a u16 family (AF_UNIX = 1), then the path;
// a leading '@' becomes the abstract namespace's NUL.
function unix_connect(path) {
  const sys = io_sys();
  const bytes = new TextEncoder().encode(path);
  if (bytes.length === 0 || bytes.length >= 108 || bytes.includes(0)) {
    return io_fail(22);
  }
  const at = new Uint8Array(110);
  at[0] = 1;
  at.set(bytes, 2);
  const abstract = bytes[0] === 64;
  if (abstract) {
    at[2] = 0;
  }
  const size = 2 + bytes.length + (abstract ? 0 : 1);
  const fd = sys.socket(1, 1 | 0x80000, 0);
  if (fd < 0) {
    return io_fail(sys.errno());
  }
  if (sys.connect(fd, sys.ptr(at), size) < 0
    || sys.fcntl(fd, 4, sys.fcntl(fd, 3, 0) | 0x800) < 0) {
    const code = sys.errno();
    sys.close(fd);
    return io_fail(code);
  }
  return io_done(fd);
}

io_eff(CID(Unix.connect), unix_connect);
