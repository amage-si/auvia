// Auvia native bridge: Unix.connect
// ==================================
//
// Opens a Unix-domain stream socket for D-Bus. A leading '@' selects the
// Linux abstract namespace. connect(2) on a local socket completes at once,
// so it runs on the event loop; the socket is then made non-blocking for
// Unix.poll_bytes and TCP.send_bytes. Answers Done{socket} or Fail{errno}.

#include <stddef.h>
#include <sys/un.h>
#include <unistd.h>

Term auvia_unix_connect_run(Env e, Term* f, IoWork* w) {
  u64                len  = 0;
  char*              path = io_cstr(e, f[0], &len);
  struct sockaddr_un at;
  memset(&at, 0, sizeof(at));
  at.sun_family = AF_UNIX;
  if (io_nul(path, len) || len == 0 || len >= sizeof(at.sun_path)) {
    free(path);
    return io_fail(e, EINVAL, NULL);
  }
  int abstract = path[0] == '@';
  memcpy(at.sun_path, path, len);
  free(path);
  if (abstract) {
    at.sun_path[0] = 0;
  }
  socklen_t size = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + len
    + (abstract ? 0 : 1));
  int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) {
    return io_fail(e, (u32)errno, NULL);
  }
  if (connect(fd, (struct sockaddr*)&at, size) < 0
    || fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) < 0) {
    u32 err = (u32)errno;
    close(fd);
    return io_fail(e, err, NULL);
  }
  return io_done(e, io_hand(fd));
}

static void __attribute__((constructor)) auvia_unix_connect_use(void) {
  io_eff(CID(Unix.connect), auvia_unix_connect_run, 0);
}
