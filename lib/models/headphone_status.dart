enum HeadphoneType {
  none,
  wired,
  bluetooth,
}

class HeadphoneStatus {
  final bool isConnected;
  final HeadphoneType type;
  final String deviceName;

  const HeadphoneStatus({
    required this.isConnected,
    required this.type,
    required this.deviceName,
  });

  const HeadphoneStatus.disconnected()
      : isConnected = false,
        type = HeadphoneType.none,
        deviceName = '';

  String get spokenDescription {
    if (!isConnected) {
      return 'No headphones connected. Audio is playing through phone speaker.';
    }
    switch (type) {
      case HeadphoneType.wired:
        return 'Wired headphones connected. Directional voice guidance is private.';
      case HeadphoneType.bluetooth:
        final name = deviceName.isNotEmpty ? deviceName : 'Bluetooth headphones';
        return '$name connected. Directional voice guidance is private.';
      case HeadphoneType.none:
        return 'No headphones connected. Using phone speaker.';
    }
  }

  String get displayLabel {
    if (!isConnected) return 'Speaker Mode';
    switch (type) {
      case HeadphoneType.wired:
        return 'Wired Headset';
      case HeadphoneType.bluetooth:
        return deviceName.isNotEmpty ? deviceName : 'Bluetooth Headset';
      case HeadphoneType.none:
        return 'Speaker Mode';
    }
  }
}
