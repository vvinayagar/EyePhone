import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'frame_source.dart';

/// A UVC camera attached over USB OTG.
///
/// Android surfaces USB video-class cameras through Camera2 as EXTERNAL-facing cameras,
/// so they can be driven with the ordinary camera plugin rather than a JNI/libuvc stack.
/// That keeps this pure Dart, but it does mean support is decided by the phone's OEM:
/// some vendors never expose external cameras at all. [findExternalCameras] returning
/// empty with a camera plugged in means the device does not support it — not a bug here.
class UsbCameraSource extends FrameSource {
  CameraController? _controller;
  CameraDescription? _camera;
  bool _ready = false;

  /// Preferred resolution. Medium keeps capture fast; the vision model sees a downscaled
  /// frame anyway, and USB bandwidth on OTG is often the bottleneck.
  final ResolutionPreset resolution;

  UsbCameraSource({this.resolution = ResolutionPreset.medium});

  @override
  CameraSourceKind get kind => CameraSourceKind.usb;

  @override
  String get description => _camera?.name ?? 'No USB camera detected';

  @override
  bool get isReady =>
      _ready && _controller != null && _controller!.value.isInitialized;

  /// The live controller, so the viewfinder can show a preview.
  CameraController? get controller => _controller;

  /// Lists cameras Android reports as external — i.e. plugged in over USB.
  static Future<List<CameraDescription>> findExternalCameras() async {
    try {
      final cameras = await availableCameras();
      return cameras
          .where((c) => c.lensDirection == CameraLensDirection.external)
          .toList();
    } catch (e) {
      debugPrint('Could not enumerate cameras: $e');
      return const [];
    }
  }

  @override
  Future<bool> initialize() async {
    try {
      final external = await findExternalCameras();
      if (external.isEmpty) {
        _ready = false;
        _camera = null;
        return false;
      }

      // Rebuild if a different camera was plugged in since last time.
      if (_controller != null && _camera?.name == external.first.name) {
        if (_controller!.value.isInitialized) {
          _ready = true;
          return true;
        }
      }

      await _disposeController();

      _camera = external.first;
      _controller = CameraController(
        _camera!,
        resolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _controller!.initialize();
      _ready = true;
      return true;
    } catch (e) {
      debugPrint('USB camera initialize error: $e');
      await _disposeController();
      _ready = false;
      return false;
    }
  }

  @override
  Future<Uint8List?> captureFrame() async {
    if (!isReady) {
      final ok = await initialize();
      if (!ok) return null;
    }
    try {
      if (_controller!.value.isTakingPicture) return null;
      final file = await _controller!.takePicture();
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('USB camera capture error: $e');
      // A yanked cable surfaces here; drop the controller so the next call re-detects.
      await _disposeController();
      _ready = false;
      return null;
    }
  }

  Future<void> _disposeController() async {
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
  }

  @override
  Future<void> dispose() async {
    await _disposeController();
    _ready = false;
  }
}
