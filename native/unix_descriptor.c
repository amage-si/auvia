// Auvia native bridge: Unix.descriptor
// =====================================
//
// The socket's file descriptor number, for an event loop that waits on it
// beside other sources (Ankra's `watch`). The socket is handed back beside
// the number; nothing is read or changed.

Term auvia_unix_descriptor_run(Env e, Term* f, IoWork* w) {
  intptr_t fd = io_hand_v(f[0]);
  return io_tup(e, io_hand(fd), (Term)(u32)fd);
}

static void __attribute__((constructor)) auvia_unix_descriptor_use(void) {
  io_eff(CID(Unix.descriptor), auvia_unix_descriptor_run);
}
