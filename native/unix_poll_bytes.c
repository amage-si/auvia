// Auvia native bridge: Unix.poll_bytes
// =====================================
//
// recv(2) with a deadline, answering raw bytes (no UTF-8 decoding: D-Bus is
// binary). A wake that finds data answers Some{bytes}; Some{[]} is the
// peer's close; past the deadline it answers None{}. The pattern follows
// Base's tcp_poll.c. The socket is handed back beside the result.

static Term auvia_unix_poll_end(Env e, IoWork* w, Term r) {
  free(w->data);
  return io_tup(e, io_hand(w->hand), r);
}

static Term auvia_unix_poll_more(Env e, IoWork* w) {
  int fd  = (int)w->hand;
  u64 at  = w->time;
  w->size = io_sys_end(w, recv(fd, w->data, (size_t)w->made, 0));
  if (w->code == EAGAIN) {
    return io_tick() < at ? io_wait_on(w, fd, POLLIN, at, auvia_unix_poll_more)
      : auvia_unix_poll_end(e, w, io_done(e, term_pak(CID(None), 0)));
  }
  return auvia_unix_poll_end(e, w,
    io_res(e, w, io_box(e, CID(Some), io_list(e, w->data, w->size))));
}

Term auvia_unix_poll_bytes_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  if (f[1] == 0) {
    return io_tup(e, io_hand(w->hand), io_fail(e, EINVAL, NULL));
  }
  w->made = f[1] < INT32_MAX ? (intptr_t)f[1] : INT32_MAX;
  w->data = io_mem(malloc((size_t)w->made));
  w->code = 0;
  return io_wait_on(w, (int)w->hand, POLLIN,
    io_tick() + (u64)f[2] * 1000000ull, auvia_unix_poll_more);
}

static void __attribute__((constructor)) auvia_unix_poll_bytes_use(void) {
  io_eff(CID(Unix.poll_bytes), auvia_unix_poll_bytes_run, 0);
}
