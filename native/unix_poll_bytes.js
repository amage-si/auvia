// Auvia native bridge: Unix.poll_bytes (JS lane)
// recv with a deadline, answering raw bytes; mirrors Base's tcp_poll.js.
function unix_poll_bytes(socket, max, ms, k) {
  if (Number(max) === 0) {
    return io_tup(socket, io_fail(22));
  }
  const sys = io_sys();
  const b = new Uint8Array(Number(max));
  const at = performance.now() + Number(ms);
  const go = () => {
    const n = Number(sys.recv(socket, sys.ptr(b), Number(max), 0));
    if (n >= 0) {
      return io_tup(socket, io_done({ $: CID(Some), value: io_list(b, n) }));
    }
    const code = sys.errno();
    if (code !== 11) {
      return io_tup(socket, io_fail(code));
    }
    if (performance.now() >= at) {
      return io_tup(socket, io_done({ $: CID(None) }));
    }
    io_park_on(socket, false, k, go, at);
    return undefined;
  };
  return go();
}

io_eff(CID(Unix.poll_bytes), unix_poll_bytes);
