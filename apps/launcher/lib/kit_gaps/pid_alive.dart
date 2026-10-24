// KIT GAP: is the process behind a roster entry really there? Roster.scan() says `live` while the heartbeat is under
// 15 s old, so a crashed app looks live for up to 15 s. Asking the OS finds it on the next refresh. Only meaningful on the
// same machine and user; a reused pid reads as alive (the entry holds no process start time). The Kit could offer this as
// `RosterRecord.processAlive` (or hold a control socket per app, which proves liveness without a pid).
import 'dart:io';

bool pidAliveViaKill(int pid) {
  if (Platform.isWindows) return true; // no cheap check; the heartbeat alone has to do
  try {
    return Process.runSync('kill', ['-0', '$pid']).exitCode == 0;
  } on ProcessException {
    return true;
  }
}
