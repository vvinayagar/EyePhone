import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../utils/fisheye_corrector.dart';
import 'camera_service.dart';
import 'frame_source.dart';
import 'network_camera_source.dart';
import 'usb_camera_source.dart';

/// Chooses which camera supplies frames and applies lens correction.
///
/// Holds one rule that matters more than the rest: if the selected remote camera fails,
/// capture falls back to the phone's own camera rather than returning nothing. A user
/// walking with this should never be left with no eyes because a WiFi camera dropped off
/// the network or a USB cable worked loose.
class CameraSourceManager extends ChangeNotifier {
  final AppSettings settings;
  final CameraService deviceCamera;

  NetworkCameraSource? _network;
  UsbCameraSource? _usb;

  /// True when the last capture had to fall back to the phone camera.
  bool _usingFallback = false;
  bool get usingFallback => _usingFallback;

  /// Set when a remote source failed, for display and for the spoken status.
  String? _lastSourceError;
  String? get lastSourceError => _lastSourceError;

  CameraSourceManager({required this.settings, required this.deviceCamera});

  CameraSourceKind get activeKind => settings.cameraSource;

  /// The USB controller, so the viewfinder can show its preview.
  UsbCameraSource? get usbSource => _usb;

  /// Builds (or rebuilds) the remote source objects from current settings.
  Future<void> applySettings() async {
    await _network?.dispose();
    _network = null;

    if (settings.networkCameraUrl.trim().isNotEmpty) {
      _network = NetworkCameraSource(
        url: settings.networkCameraUrl,
        username: settings.networkCameraUsername,
        password: settings.networkCameraPassword,
      );
      await _network!.initialize();
    }

    if (settings.cameraSource == CameraSourceKind.usb) {
      _usb ??= UsbCameraSource();
      await _usb!.initialize();
    }

    _usingFallback = false;
    _lastSourceError = null;
    notifyListeners();
  }

  /// The source matching the user's choice, or null if it is not configured.
  FrameSource? get _selectedRemote {
    switch (settings.cameraSource) {
      case CameraSourceKind.network:
        return _network;
      case CameraSourceKind.usb:
        return _usb;
      case CameraSourceKind.device:
        return null;
    }
  }

  /// Captures one frame from the selected source, correcting the lens if configured.
  Future<Uint8List?> captureFrame() async {
    Uint8List? raw;
    final remote = _selectedRemote;

    if (settings.cameraSource != CameraSourceKind.device && remote != null) {
      try {
        raw = await remote.captureFrame();
      } catch (e) {
        debugPrint('Remote camera capture failed: $e');
        raw = null;
      }

      if (raw == null || raw.isEmpty) {
        // Fall back rather than leaving the user blind.
        _usingFallback = true;
        _lastSourceError =
            '${settings.cameraSource.label} did not respond. Using phone camera.';
        notifyListeners();
        raw = await deviceCamera.captureImageBytes();
      } else if (_usingFallback) {
        _usingFallback = false;
        _lastSourceError = null;
        notifyListeners();
      }
    } else {
      raw = await deviceCamera.captureImageBytes();
    }

    if (raw == null || raw.isEmpty) return null;
    return _applyLensCorrection(raw);
  }

  /// Runs fisheye correction off the UI thread — remapping every pixel would otherwise
  /// stutter the preview and the audio cues during continuous guidance.
  Future<Uint8List> _applyLensCorrection(Uint8List frame) async {
    if (!settings.fisheyeCorrectionEnabled || settings.fisheyeStrength <= 0) {
      return frame;
    }
    try {
      return await compute(
        _correctInIsolate,
        _FisheyeJob(frame, settings.fisheyeStrength),
      );
    } catch (e) {
      debugPrint('Fisheye correction failed: $e');
      return frame;
    }
  }

  /// Verifies a source is reachable, for the settings screen.
  Future<FrameSourceTestResult> testSource(CameraSourceKind kind) async {
    switch (kind) {
      case CameraSourceKind.device:
        final ok = await deviceCamera.initialize();
        final frame = ok ? await deviceCamera.captureImageBytes() : null;
        return FrameSourceTestResult(
          success: frame != null,
          message: frame != null ? 'Working.' : 'Phone camera unavailable.',
          frameBytes: frame?.length,
        );
      case CameraSourceKind.network:
        if (settings.networkCameraUrl.trim().isEmpty) {
          return const FrameSourceTestResult(
            success: false,
            message: 'Enter the camera address first.',
          );
        }
        final source = NetworkCameraSource(
          url: settings.networkCameraUrl,
          username: settings.networkCameraUsername,
          password: settings.networkCameraPassword,
        );
        final result = await source.test();
        await source.dispose();
        return result;
      case CameraSourceKind.usb:
        final cameras = await UsbCameraSource.findExternalCameras();
        if (cameras.isEmpty) {
          return const FrameSourceTestResult(
            success: false,
            message: 'No USB camera detected. Check the OTG cable, and note that some '
                'phones never expose USB cameras to apps.',
          );
        }
        final source = UsbCameraSource();
        final result = await source.test();
        await source.dispose();
        return result;
    }
  }

  @override
  void dispose() {
    _network?.dispose();
    _usb?.dispose();
    super.dispose();
  }
}

/// Payload for the correction isolate — `compute` takes a single argument.
class _FisheyeJob {
  final Uint8List bytes;
  final double strength;
  const _FisheyeJob(this.bytes, this.strength);
}

Uint8List _correctInIsolate(_FisheyeJob job) =>
    FisheyeCorrector.correct(job.bytes, strength: job.strength);
