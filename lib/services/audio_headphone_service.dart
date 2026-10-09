import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/headphone_status.dart';

class AudioHeadphoneService {
  static const MethodChannel _channel = MethodChannel('com.eyephone.app/headphone');

  final ValueNotifier<HeadphoneStatus> statusNotifier =
      ValueNotifier<HeadphoneStatus>(const HeadphoneStatus.disconnected());

  VoidCallback? onHeadsetButtonTriggered;
  Function(HeadphoneStatus status)? onStatusChanged;

  AudioHeadphoneService() {
    _initChannel();
    _initAudioSession();
  }

  void _initChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onHeadphoneStateChanged':
          if (call.arguments is Map) {
            final map = Map<String, dynamic>.from(call.arguments as Map);
            _updateFromMap(map);
          }
          break;
        case 'onHeadsetButtonPressed':
          debugPrint('EyePhone: Headset button pressed on headphone/earbud');
          onHeadsetButtonTriggered?.call();
          break;
      }
    });

    // Check status on startup
    checkStatus();
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp |
            AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.assistanceAccessibility,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ));

      // Listen to devices changed via audio_session
      session.devicesChangedEventStream.listen((_) {
        checkStatus();
      });
    } catch (e) {
      debugPrint('Error configuring audio session: $e');
    }
  }

  Future<HeadphoneStatus> checkStatus() async {
    try {
      final res = await _channel.invokeMethod('getHeadphoneStatus');
      if (res is Map) {
        final map = Map<String, dynamic>.from(res);
        final status = _updateFromMap(map);
        return status;
      }
    } on MissingPluginException {
      // Running on non-Android platform (e.g. Windows/macOS desktop development)
      debugPrint('Headphone native channel not available on this platform');
    } catch (e) {
      debugPrint('Error checking headphone status: $e');
    }
    return statusNotifier.value;
  }

  HeadphoneStatus _updateFromMap(Map<String, dynamic> map) {
    final connected = map['connected'] as bool? ?? false;
    final typeStr = map['type'] as String? ?? 'none';
    final name = map['name'] as String? ?? '';

    HeadphoneType type = HeadphoneType.none;
    if (typeStr == 'wired') {
      type = HeadphoneType.wired;
    } else if (typeStr == 'bluetooth') {
      type = HeadphoneType.bluetooth;
    }

    final newStatus = HeadphoneStatus(
      isConnected: connected,
      type: type,
      deviceName: name,
    );

    statusNotifier.value = newStatus;
    onStatusChanged?.call(newStatus);
    return newStatus;
  }

  void dispose() {
    statusNotifier.dispose();
  }
}
