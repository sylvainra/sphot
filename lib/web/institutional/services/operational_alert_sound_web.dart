// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

Future<void> playOperationalFogHorn() async {
  try {
    const sampleRate = 8000;
    const durationSeconds = 1.6;
    final sampleCount = (sampleRate * durationSeconds).round();
    final pcmBytes = sampleCount * 2;
    final bytes = Uint8List(44 + pcmBytes);
    final data = ByteData.sublistView(bytes);

    void writeAscii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        data.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    writeAscii(0, 'RIFF');
    data.setUint32(4, 36 + pcmBytes, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, pcmBytes, Endian.little);

    for (var index = 0; index < sampleCount; index++) {
      final time = index / sampleRate;
      final fadeIn = (time / 0.08).clamp(0.0, 1.0);
      final fadeOut =
          ((durationSeconds - time) / 0.22).clamp(0.0, 1.0);
      final envelope = math.min(fadeIn, fadeOut);
      final slowPulse = 0.80 + 0.20 * math.sin(2 * math.pi * 0.65 * time);
      final signal =
          math.sin(2 * math.pi * 110 * time) +
          0.42 * math.sin(2 * math.pi * 220 * time) +
          0.20 * math.sin(2 * math.pi * 55 * time);
      final sample = (signal / 1.62 * envelope * slowPulse * 28000)
          .round()
          .clamp(-32768, 32767)
          .toInt();
      data.setInt16(44 + index * 2, sample, Endian.little);
    }

    final source = 'data:audio/wav;base64,${base64Encode(bytes)}';
    final audio = html.AudioElement(source)..volume = 0.9;
    await audio.play();
  } catch (_) {
    // Les navigateurs peuvent bloquer l'autoplay sans interaction préalable.
  }
}
