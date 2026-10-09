import 'dart:async';
import 'package:flutter/foundation.dart';

/// Where camera frames come from.
///
/// EyePhone only ever needs a single still JPEG per scan — it never needs a live video
/// stream — which is what makes remote cameras practical at all. Anything that can hand
/// over a JPEG can be an eye for the user: the built-in camera, a WiFi/IP camera clipped
/// to a bag strap, or a USB camera on an OTG cable.
enum CameraSourceKind {
  /// The phone's own camera.
  device,

  /// An HTTP snapshot or MJPEG endpoint on the local network.
  network,

  /// A UVC camera over USB OTG, exposed by Android as an external camera.
  usb,
}

extension CameraSourceKindExtension on CameraSourceKind {
  String get label {
    switch (this) {
      case CameraSourceKind.device:
        return 'Phone camera';
      case CameraSourceKind.network:
        return 'Wireless / IP camera';
      case CameraSourceKind.usb:
        return 'USB camera (OTG)';
    }
  }

  String get spokenLabel {
    switch (this) {
      case CameraSourceKind.device:
        return 'phone camera';
      case CameraSourceKind.network:
        return 'wireless camera';
      case CameraSourceKind.usb:
        return 'U S B camera';
    }
  }
}

/// Result of probing a camera source, used by the settings screen.
class FrameSourceTestResult {
  final bool success;
  final String message;
  final int? millis;
  final int? frameBytes;

  const FrameSourceTestResult({
    required this.success,
    required this.message,
    this.millis,
    this.frameBytes,
  });
}

/// A thing that can produce a JPEG frame on demand.
abstract class FrameSource {
  CameraSourceKind get kind;

  /// Human-readable description of the specific device, e.g. the URL or camera name.
  String get description;

  /// True when [captureFrame] can be expected to succeed.
  bool get isReady;

  /// Prepares the source. Returns false if it cannot be used.
  Future<bool> initialize();

  /// Grabs one frame as JPEG bytes, or null on failure.
  Future<Uint8List?> captureFrame();

  /// Checks the source is reachable and reports timing, for the settings screen.
  Future<FrameSourceTestResult> test() async {
    final sw = Stopwatch()..start();
    try {
      final ok = await initialize();
      if (!ok) {
        sw.stop();
        return const FrameSourceTestResult(
          success: false,
          message: 'Could not open this camera.',
        );
      }
      final frame = await captureFrame();
      sw.stop();
      if (frame == null || frame.isEmpty) {
        return const FrameSourceTestResult(
          success: false,
          message: 'Connected, but no image was returned.',
        );
      }
      return FrameSourceTestResult(
        success: true,
        message: 'Working.',
        millis: sw.elapsedMilliseconds,
        frameBytes: frame.length,
      );
    } catch (e) {
      sw.stop();
      debugPrint('Frame source test failed: $e');
      return FrameSourceTestResult(success: false, message: _friendlyError(e));
    }
  }

  Future<void> dispose();

  static String _friendlyError(Object e) {
    final m = e.toString().toLowerCase();
    if (m.contains('timeout')) {
      return 'Timed out. Check the camera is powered on and on the same network.';
    }
    if (m.contains('socket') || m.contains('refused') || m.contains('unreachable')) {
      return 'Could not reach that address. Check the IP and port.';
    }
    if (m.contains('401') || m.contains('403') || m.contains('unauthor')) {
      return 'Camera refused the connection. Check the username and password.';
    }
    if (m.contains('404')) {
      return 'Address reached, but no image at that path.';
    }
    return 'Connection failed: $e';
  }
}
