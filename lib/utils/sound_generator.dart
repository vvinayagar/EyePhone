import 'dart:math' as math;
import 'dart:typed_data';

/// Generates PCM WAV audio in memory with optional stereo panning (-1.0 left to +1.0 right).
/// Enables spatial 3D audio cues in headphones for visually impaired navigation.
class SoundGenerator {
  static const int sampleRate = 44100;

  static Uint8List createToneWav({
    required double frequency,
    required double durationSeconds,
    double volume = 0.5,
    double pan = 0.0, // -1.0 (pure left) to 1.0 (pure right)
  }) {
    final int numSamples = (sampleRate * durationSeconds).toInt();
    final int numChannels = 2; // Stereo for spatial headphone audio
    final int bytesPerSample = 2; // 16-bit PCM
    final int dataSize = numSamples * numChannels * bytesPerSample;
    final int totalSize = 36 + dataSize;

    final ByteData byteData = ByteData(44 + dataSize);

    // RIFF header
    byteData.setUint8(0, 0x52); // 'R'
    byteData.setUint8(1, 0x49); // 'I'
    byteData.setUint8(2, 0x46); // 'F'
    byteData.setUint8(3, 0x46); // 'F'
    byteData.setUint32(4, totalSize, Endian.little);
    byteData.setUint8(8, 0x57);  // 'W'
    byteData.setUint8(9, 0x41);  // 'A'
    byteData.setUint8(10, 0x56); // 'V'
    byteData.setUint8(11, 0x45); // 'E'

    // 'fmt ' chunk
    byteData.setUint8(12, 0x66); // 'f'
    byteData.setUint8(13, 0x6D); // 'm'
    byteData.setUint8(14, 0x74); // 't'
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    byteData.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    byteData.setUint16(22, numChannels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * numChannels * bytesPerSample, Endian.little); // ByteRate
    byteData.setUint16(32, numChannels * bytesPerSample, Endian.little); // BlockAlign
    byteData.setUint16(34, bytesPerSample * 8, Endian.little); // BitsPerSample

    // 'data' chunk
    byteData.setUint8(36, 0x64); // 'd'
    byteData.setUint8(37, 0x61); // 'a'
    byteData.setUint8(38, 0x74); // 't'
    byteData.setUint8(39, 0x61); // 'a'
    byteData.setUint32(40, dataSize, Endian.little);

    // Calculate left/right volume multipliers based on pan
    // pan ranges from -1.0 (left) to 1.0 (right)
    final clampedPan = pan.clamp(-1.0, 1.0);
    final double leftVol = volume * math.cos((clampedPan + 1.0) * math.pi / 4);
    final double rightVol = volume * math.sin((clampedPan + 1.0) * math.pi / 4);

    int offset = 44;
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      // Apply smooth attack and decay envelope to prevent audio clicking
      double envelope = 1.0;
      final double attackTime = 0.015;
      final double decayTime = 0.02;
      if (t < attackTime) {
        envelope = t / attackTime;
      } else if (t > durationSeconds - decayTime) {
        envelope = (durationSeconds - t) / decayTime;
      }
      envelope = envelope.clamp(0.0, 1.0);

      final double sample = math.sin(2 * math.pi * frequency * t) * envelope;
      final int leftSampleInt = (sample * leftVol * 32767).toInt().clamp(-32768, 32767);
      final int rightSampleInt = (sample * rightVol * 32767).toInt().clamp(-32768, 32767);

      byteData.setInt16(offset, leftSampleInt, Endian.little);
      byteData.setInt16(offset + 2, rightSampleInt, Endian.little);
      offset += 4;
    }

    return byteData.buffer.asUint8List();
  }
}
