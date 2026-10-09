import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'frame_source.dart';

/// A camera reached over WiFi or the local network.
///
/// Handles the two things cheap network cameras actually serve:
///   * a snapshot endpoint that returns one JPEG per request (ESP32-CAM `/capture`,
///     most IP cameras' `/snapshot.jpg`, "IP Webcam" `/shot.jpg`)
///   * an MJPEG stream, from which the first complete frame is taken
///
/// RTSP is deliberately not supported: it needs a full media stack, and every camera
/// worth using for this also exposes HTTP. See the note in the settings screen.
class NetworkCameraSource extends FrameSource {
  /// JPEG markers used to find a frame inside an MJPEG multipart stream.
  static const int _jpegSoi0 = 0xFF;
  static const int _jpegSoi1 = 0xD8;
  static const int _jpegEoi1 = 0xD9;

  final String url;
  final String? username;
  final String? password;
  final Duration timeout;

  final http.Client _client;
  bool _ready = false;

  NetworkCameraSource({
    required this.url,
    this.username,
    this.password,
    this.timeout = const Duration(seconds: 8),
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  CameraSourceKind get kind => CameraSourceKind.network;

  @override
  String get description => url;

  @override
  bool get isReady => _ready;

  /// Normalizes what the user typed into a usable URL.
  ///
  /// People type "192.168.1.50:8080" or "192.168.1.50" far more often than a full URL,
  /// and asking a blind user to type "http://" exactly is a poor trade.
  static String normalizeUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;
    if (!value.contains('://')) value = 'http://$value';

    final uri = Uri.tryParse(value);
    if (uri == null) return value;

    // A bare host with no path is almost always the "IP Webcam" Android app, whose
    // snapshot path is /shot.jpg. It is the most common way people repurpose a spare
    // phone as a remote camera, so default to it rather than failing.
    if (uri.path.isEmpty || uri.path == '/') {
      return uri.replace(path: '/shot.jpg').toString();
    }
    return value;
  }

  Map<String, String> get _headers {
    if (username == null || username!.isEmpty) return const {};
    final credentials = base64Encode(utf8.encode('$username:${password ?? ''}'));
    return {'Authorization': 'Basic $credentials'};
  }

  @override
  Future<bool> initialize() async {
    _ready = url.trim().isNotEmpty;
    return _ready;
  }

  @override
  Future<Uint8List?> captureFrame() async {
    if (url.trim().isEmpty) return null;
    final target = Uri.parse(normalizeUrl(url));

    final request = http.Request('GET', target)..headers.addAll(_headers);
    final response = await _client.send(request).timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final contentType = (response.headers['content-type'] ?? '').toLowerCase();

    // Plain snapshot: the whole body is the image.
    if (!contentType.contains('multipart')) {
      final bytes = await response.stream.toBytes().timeout(timeout);
      _ready = bytes.isNotEmpty;
      return bytes.isEmpty ? null : bytes;
    }

    // MJPEG: pull from the stream only until one complete JPEG has arrived, then stop.
    // Reading the whole stream would never terminate — it is an endless broadcast.
    final frame = await _firstJpegFromStream(response.stream).timeout(timeout);
    _ready = frame != null;
    return frame;
  }

  /// Scans an MJPEG byte stream for the first complete JPEG (SOI..EOI).
  Future<Uint8List?> _firstJpegFromStream(http.ByteStream stream) async {
    final buffer = BytesBuilder();
    final completer = Completer<Uint8List?>();
    late StreamSubscription<List<int>> sub;

    // Guard against a stream that connects but never delivers a full frame.
    const maxBytes = 8 * 1024 * 1024;

    sub = stream.listen(
      (chunk) {
        buffer.add(chunk);
        if (buffer.length > maxBytes) {
          if (!completer.isCompleted) completer.complete(null);
          sub.cancel();
          return;
        }

        final bytes = buffer.toBytes();
        final start = _indexOfSoi(bytes);
        if (start < 0) return;
        final end = _indexOfEoi(bytes, start + 2);
        if (end < 0) return;

        if (!completer.isCompleted) {
          completer.complete(Uint8List.sublistView(bytes, start, end + 2));
        }
        sub.cancel();
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  static int _indexOfSoi(Uint8List bytes) {
    for (var i = 0; i + 1 < bytes.length; i++) {
      if (bytes[i] == _jpegSoi0 && bytes[i + 1] == _jpegSoi1) return i;
    }
    return -1;
  }

  static int _indexOfEoi(Uint8List bytes, int from) {
    for (var i = from; i + 1 < bytes.length; i++) {
      if (bytes[i] == _jpegSoi0 && bytes[i + 1] == _jpegEoi1) return i;
    }
    return -1;
  }

  @override
  Future<void> dispose() async {
    _ready = false;
    _client.close();
  }
}

