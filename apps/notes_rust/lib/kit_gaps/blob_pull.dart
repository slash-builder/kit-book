// Copied from apps/notepad/lib/kit_gaps/blob_pull.dart (an app does not import another app). The gap is unchanged; here the
// "blob" is a block export from the Rust core, and the tag is a constant because an export of given hashes never changes.
// KIT GAP: moving state bigger than one message. The Kit has no large transfer (spec 6.1: "no transfer for state over 1 MiB"; on
// Hearth the usable payload is 64 KiB minus the header, and the hub drops the connection above 1 MiB), no way to ask a provider
// for its maximum payload (`partBytes` below is a constant the app guessed), no acknowledgement and no replay. The only
// reliable primitive is request/reply, so this PULLS: the receiver asks for part 0, 1, 2 ... one reply at a time, each carrying
// an opaque version `tag`; a changed tag mid-way means the sender edited it meanwhile and the pull restarts. Bounded by
// `maxBytes` before allocating. Base64 inside the Kit's own base64 costs about 1.8x on the wire (24 KiB of text is a 44 KB
// frame). Candidate: `hub.pull(peer, key)` / `hub.serveBlob(...)` with a provider-declared maximum, in the Kit.
import 'dart:convert';
import 'dart:typed_data';

import 'package:application_kit/application_kit.dart';

class PulledBlob {
  PulledBlob(this.tag, this.bytes);

  /// The sender's version tag for these bytes (decoded JSON, opaque here).
  final Object? tag;
  final Uint8List bytes;
}

/// Pulls one blob from [peer]. Returns null when the sender says it is gone or too large, or kept changing it for [attempts]
/// tries. Throws [FormatException] for a reply that is not what a well-behaved sender sends (the caller counts it), and
/// [PeerError] when the peer is lost or does not answer.
Future<PulledBlob?> pullBlob(
  PeerHub hub,
  Peer peer, {
  required String kind,
  required Map<String, Object?> key,
  required int maxBytes,
  required int partBytes,
  required Duration timeout,
  int attempts = 3,
  void Function()? onPart,
}) async {
  final maxParts = maxBytes ~/ partBytes + 1;
  for (var attempt = 0; attempt < attempts; attempt++) {
    final buf = BytesBuilder(copy: false);
    String? tagJson;
    Object? tag;
    var parts = 1, stale = false;
    for (var i = 0; i < parts; i++) {
      final reply = await hub.request(peer, PeerJson.encode({...key, 'part': i, 'tag': tag}), kind: kind, schema: 1, timeout: timeout);
      onPart?.call();
      final j = reply.jsonBody;
      if (j is! Map) throw const FormatException('reply is not an object');
      if (j['ok'] != true) {
        if (j['reason'] == 'stale') {
          stale = true;
          break;
        }
        return null;
      }
      final n = j['parts'], data = j['data'];
      if (n is! int || n < 1 || n > maxParts || data is! String) throw const FormatException('bad part header');
      final here = jsonEncode(j['tag']);
      if (i == 0) {
        tag = j['tag'];
        tagJson = here;
        parts = n;
      } else if (here != tagJson || n != parts) {
        stale = true;
        break;
      }
      buf.add(base64Decode(data)); // FormatException on bad base64
      if (buf.length > maxBytes) throw const FormatException('blob larger than the limit');
    }
    if (!stale) return PulledBlob(tag, buf.takeBytes());
  }
  return null;
}

/// The reply to one `pullBlob` request for [bytes] at version [tag]. [wantTag] is what the puller pinned (null on part 0).
Map<String, Object?> blobPartReply({required Uint8List bytes, required int part, required int partBytes, required Object? tag, required Object? wantTag}) {
  if (wantTag != null && jsonEncode(wantTag) != jsonEncode(tag)) return {'ok': false, 'reason': 'stale'};
  final parts = (bytes.length + partBytes - 1) ~/ partBytes;
  if (part >= parts) return {'ok': false, 'reason': 'gone'};
  final end = (part + 1) * partBytes > bytes.length ? bytes.length : (part + 1) * partBytes;
  return {'ok': true, 'tag': tag, 'parts': parts, 'data': base64Encode(bytes.sublist(part * partBytes, end))};
}
