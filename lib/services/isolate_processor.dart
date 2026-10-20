import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:image/image.dart' as img;

class IsolateFilterPayload {
  final Uint8List bytes;
  final int filterIndex;
  IsolateFilterPayload(this.bytes, this.filterIndex);
}

Uint8List applyFilterInBackgroundIsolate(IsolateFilterPayload payload) {
  final decoded = img.decodeImage(payload.bytes);
  if (decoded == null) return payload.bytes;

  img.Image working = decoded.clone();
  if (payload.filterIndex == 1) {
    working = img.adjustColor(working, contrast: 1.30, saturation: 1.18, brightness: 1.04);
  } else if (payload.filterIndex == 2) {
    working = img.grayscale(working);
  } else if (payload.filterIndex == 3) {
    working = img.grayscale(working);
    working = img.luminanceThreshold(working, threshold: 0.53);
  }
  return Uint8List.fromList(img.encodeJpg(working, quality: 90));
}

class IsolateWarpPayload {
  final Uint8List bytes;
  final List<double> normCoords;
  IsolateWarpPayload(this.bytes, this.normCoords);
}

Uint8List performPerspectiveWarpInIsolate(IsolateWarpPayload payload) {
  final srcImg = img.decodeImage(payload.bytes);
  if (srcImg == null) return payload.bytes;

  final w = srcImg.width.toDouble();
  final h = srcImg.height.toDouble();
  final c = payload.normCoords;

  final p0 = Offset(c[0] * w, c[1] * h);
  final p1 = Offset(c[2] * w, c[3] * h);
  final p2 = Offset(c[4] * w, c[5] * h);
  final p3 = Offset(c[6] * w, c[7] * h);

  final outW = math.max(240, math.max((p1 - p0).distance, (p2 - p3).distance).round());
  final outH = math.max(240, math.max((p3 - p0).distance, (p2 - p1).distance).round());
  final dstImg = img.Image(width: outW, height: outH);

  for (int y = 0; y < outH; y++) {
    final v = y / (outH - 1);
    for (int x = 0; x < outW; x++) {
      final u = x / (outW - 1);
      final srcX = (1 - u) * (1 - v) * p0.dx + u * (1 - v) * p1.dx + u * v * p2.dx + (1 - u) * v * p3.dx;
      final srcY = (1 - u) * (1 - v) * p0.dy + u * (1 - v) * p1.dy + u * v * p2.dy + (1 - u) * v * p3.dy;
      final sx = srcX.round().clamp(0, srcImg.width - 1);
      final sy = srcY.round().clamp(0, srcImg.height - 1);
      dstImg.setPixel(x, y, srcImg.getPixel(sx, sy));
    }
  }
  return Uint8List.fromList(img.encodeJpg(dstImg, quality: 92));
}
