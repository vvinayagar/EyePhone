import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Removes fisheye barrel distortion from a frame before it is analysed.
///
/// This exists for accuracy, not looks. EyePhone's whole output format is clock bearings
/// and distances ("chair at 2 o'clock, three meters"). A fisheye lens bends straight lines
/// and pushes objects toward the centre, so an uncorrected wide-angle frame makes the
/// model report bearings that are simply wrong — and the user cannot see that it is wrong.
/// Correcting first keeps the directions trustworthy.
class FisheyeCorrector {
  /// Work at this size. The vision model receives a downscaled frame regardless, and
  /// remapping every pixel of a full-resolution image in Dart would stall the scan loop.
  static const int maxWorkingEdge = 640;

  /// Re-projects an equidistant fisheye image toward rectilinear.
  ///
  /// [strength] is how aggressive the correction is: 0 leaves the image untouched, ~0.5
  /// suits a mild wide-angle lens, and 1.0+ suits a true 180-degree fisheye. It is exposed
  /// to the user because lens geometry varies and there is no way to detect it from a
  /// single frame.
  ///
  /// Returns re-encoded JPEG bytes, or the original bytes unchanged if correction is off
  /// or the frame cannot be decoded — a scan with a slightly distorted image is far better
  /// than no scan at all.
  static Uint8List correct(
    Uint8List jpegBytes, {
    double strength = 0.6,
    int jpegQuality = 85,
  }) {
    if (strength <= 0.0) return jpegBytes;

    try {
      final decoded = img.decodeImage(jpegBytes);
      if (decoded == null) return jpegBytes;

      final source = _downscale(decoded);
      final corrected = remap(source, strength);
      return Uint8List.fromList(img.encodeJpg(corrected, quality: jpegQuality));
    } catch (e) {
      debugPrint('Fisheye correction failed, using original frame: $e');
      return jpegBytes;
    }
  }

  static img.Image _downscale(img.Image input) {
    final longest = math.max(input.width, input.height);
    if (longest <= maxWorkingEdge) return input;
    final scale = maxWorkingEdge / longest;
    return img.copyResize(
      input,
      width: (input.width * scale).round(),
      height: (input.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  /// Inverse-maps each destination pixel back into the fisheye source.
  ///
  /// Walking the destination (rather than the source) guarantees every output pixel is
  /// filled; the forward direction would leave holes that read as noise to the model.
  @visibleForTesting
  static img.Image remap(img.Image src, double strength) {
    final width = src.width;
    final height = src.height;
    final output = img.Image(width: width, height: height);

    final cx = (width - 1) / 2.0;
    final cy = (height - 1) / 2.0;
    // Normalize by the half-diagonal so the correction is symmetric on non-square frames.
    final maxRadius = math.sqrt(cx * cx + cy * cy);
    if (maxRadius <= 0) return src;

    // atan-based model: r_src = atan(r_dst * k) / atan(k), normalized so 0->0 and 1->1.
    // This pulls the stretched edges back in without moving the frame boundary.
    final k = strength * 2.0;
    final denom = math.atan(k);
    if (denom.abs() < 1e-6) return src;

    for (var y = 0; y < height; y++) {
      final dy = (y - cy) / maxRadius;
      for (var x = 0; x < width; x++) {
        final dx = (x - cx) / maxRadius;

        final rDst = math.sqrt(dx * dx + dy * dy);
        double scale;
        if (rDst < 1e-6) {
          scale = 1.0;
        } else {
          final rSrc = math.atan(rDst * k) / denom;
          scale = rSrc / rDst;
        }

        final srcX = cx + dx * scale * maxRadius;
        final srcY = cy + dy * scale * maxRadius;

        if (srcX < 0 || srcY < 0 || srcX > width - 1 || srcY > height - 1) {
          output.setPixelRgba(x, y, 0, 0, 0, 255);
          continue;
        }

        final rgb = _bilinear(src, srcX, srcY);
        output.setPixelRgba(x, y, rgb.$1, rgb.$2, rgb.$3, 255);
      }
    }
    return output;
  }

  /// Bilinear sample. Nearest-neighbour leaves jagged edges that the model can read as
  /// texture or clutter, so it is worth the extra arithmetic.
  static (int, int, int) _bilinear(img.Image src, double x, double y) {
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = math.min(x0 + 1, src.width - 1);
    final y1 = math.min(y0 + 1, src.height - 1);

    final fx = x - x0;
    final fy = y - y0;

    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);

    double blend(num a, num b, num c, num d) {
      final top = a + (b - a) * fx;
      final bottom = c + (d - c) * fx;
      return top + (bottom - top) * fy;
    }

    return (
      blend(p00.r, p10.r, p01.r, p11.r).round().clamp(0, 255),
      blend(p00.g, p10.g, p01.g, p11.g).round().clamp(0, 255),
      blend(p00.b, p10.b, p01.b, p11.b).round().clamp(0, 255),
    );
  }
}
