import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isTorchOn = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized && _controller != null && _controller!.value.isInitialized;
  bool get isTorchOn => _isTorchOn;

  Future<bool> initialize() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        debugPrint('Camera permission denied');
        return false;
      }

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        debugPrint('No cameras found on device');
        return false;
      }

      // Select back-facing camera
      final backCamera = _cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.medium, // Balanced resolution for fast AI processing & low latency
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Captures a frame snapshot and returns the JPEG bytes for Gemini analysis
  Future<Uint8List?> captureImageBytes() async {
    if (!isInitialized || _controller == null) {
      final ok = await initialize();
      if (!ok || _controller == null) return null;
    }

    try {
      if (_controller!.value.isTakingPicture) {
        return null;
      }
      final XFile file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      return bytes;
    } catch (e) {
      debugPrint('Camera capture error: $e');
      return null;
    }
  }

  Future<void> toggleTorch() async {
    if (!isInitialized || _controller == null) return;
    try {
      _isTorchOn = !_isTorchOn;
      await _controller!.setFlashMode(
        _isTorchOn ? FlashMode.torch : FlashMode.off,
      );
    } catch (e) {
      debugPrint('Torch toggle error: $e');
    }
  }

  Future<void> setTorch(bool on) async {
    if (!isInitialized || _controller == null) return;
    try {
      _isTorchOn = on;
      await _controller!.setFlashMode(
        on ? FlashMode.torch : FlashMode.off,
      );
    } catch (e) {
      debugPrint('Set torch error: $e');
    }
  }

  Future<void> dispose() async {
    try {
      if (_isTorchOn && _controller != null) {
        await _controller!.setFlashMode(FlashMode.off);
      }
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
    _isInitialized = false;
  }
}
