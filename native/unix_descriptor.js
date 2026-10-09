// Auvia native bridge: Unix.descriptor (JS lane)
// The socket is its descriptor number on this lane.
function unix_descriptor(socket) {
  return io_tup(socket, Number(socket) >>> 0);
}

io_eff(CID(Unix.descriptor), unix_descriptor);
