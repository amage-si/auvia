// Auvia native bridge: Unix.uid (JS lane)
function unix_uid() {
  return process.getuid() >>> 0;
}

io_eff(CID(Unix.uid), unix_uid);
