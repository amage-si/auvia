// Auvia native bridge: Unix.uid
// ==============================
//
// getuid(2), for the D-Bus SASL "AUTH EXTERNAL <hex(uid)>" line.

#include <unistd.h>

Term auvia_unix_uid_run(Env e, Term* f, IoWork* w) {
  return (Term)(u32)getuid();
}

static void __attribute__((constructor)) auvia_unix_uid_use(void) {
  io_eff(CID(Unix.uid), auvia_unix_uid_run, 0);
}
