import Base

# Auvia's whole native surface: a Unix-domain stream socket, a non-blocking
# byte read, and the process uid for D-Bus EXTERNAL authentication.
# Everything above the socket (SASL, D-Bus marshalling, AT-SPI) is Bend.
# Sending uses Base's TCP.send_bytes, which is plain send(2) on any socket.

# Connects to a Unix-domain stream socket. A path starting with '@' names
# the Linux abstract namespace (D-Bus "unix:abstract="). The socket is
# non-blocking and close-on-exec.
def Unix.connect(path: String) -> IO(Result<&1, &1, U32 & String, Socket>):
  import "./unix_connect.c"
  import "./unix_connect.js"

# Reads up to max bytes, waiting at most ms milliseconds. None{} means the
# deadline passed with nothing to read; Some{[]} means the peer closed.
def Unix.poll_bytes(sock: Socket, max: U32, ms: U32) ->
  IO(Socket & Result<&1, &1, U32 & String, Maybe<&2, List<&2, U32>>>):
  import "./unix_poll_bytes.c"
  import "./unix_poll_bytes.js"

# The real user id of this process.
def Unix.uid() -> IO(U32):
  import "./unix_uid.c"
  import "./unix_uid.js"
