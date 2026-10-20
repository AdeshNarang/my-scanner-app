import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/document_models.dart';
import '../services/isolate_processor.dart';

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kNavySecondary = Color(0xFF1E293B);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kBlueLight = Color(0xFFDBEAFE);
const Color kWhitePure = Colors.white;

class EightHandlePerspectiveCropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String pageTitle;
  const EightHandlePerspectiveCropScreen({super.key, required this.imageBytes, required this.pageTitle});

  @override
  State<EightHandlePerspectiveCropScreen> createState() => _EightHandlePerspectiveCropScreenState();
}

class _EightHandlePerspectiveCropScreenState extends State<EightHandlePerspectiveCropScreen> {
  List<Offset> _corners = [
    const Offset(0.08, 0.08),
    const Offset(0.92, 0.08),
    const Offset(0.92, 0.92),
    const Offset(0.08, 0.92),
  ];
  int? _activeDragIndex;
  Offset? _activeDragPixelPos;
  bool _processingWarp = false;
  ui.Image? _decodedUiImage;

  @override
  void initState() {
    super.initState();
    _decodeUiImageForLoupe();
    _detectDocumentEdgesSmart();
  }

  Future<void> _decodeUiImageForLoupe() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _decodedUiImage = frame.image);
  }

  /// Multi-ray gradient consensus algorithm
  /// Samples 7 vertical and 7 horizontal lines to find true document boundaries,
  /// ignoring isolated dark/light patterns on textured sheets or wooden desks.
  Future<void> _detectDocumentEdgesSmart() async {
    final decoded = img.decodeImage(widget.imageBytes);
    if (decoded == null) return;

    final w = decoded.width;
    final h = decoded.height;

    final List<double> topCandidates = [];
    final List<double> bottomCandidates = [];
    final List<double> leftCandidates = [];
    final List<double> rightCandidates = [];

    // Sample across horizontal positions (20% to 80%) for top and bottom edges
    for (double f = 0.20; f <= 0.80; f += 0.10) {
      final x = (w * f).round().clamp(0, w - 1);

      // Top edge scan: from 4% down to 45%
      int bestTopY = (h * 0.08).round();
      double maxGradTop = 0;
      for (int y = (h * 0.04).round(); y < (h * 0.45).round(); y += 3) {
        final p1 = decoded.getPixel(x, y);
        final p2 = decoded.getPixel(x, y + 3);
        final lum1 = (p1.r + p1.g + p1.b) / 3.0;
        final lum2 = (p2.r + p2.g + p2.b) / 3.0;
        final grad = (lum2 - lum1).abs();
        if (grad > maxGradTop && grad > 25) {
          maxGradTop = grad;
          bestTopY = y;
        }
      }
      topCandidates.add(bestTopY.toDouble());

      // Bottom edge scan: from 96% up to 55%
      int bestBottomY = (h * 0.92).round();
      double maxGradBottom = 0;
      for (int y = (h * 0.96).round(); y > (h * 0.55).round(); y -= 3) {
        final p1 = decoded.getPixel(x, y);
        final p2 = decoded.getPixel(x, y - 3);
        final lum1 = (p1.r + p1.g + p1.b) / 3.0;
        final lum2 = (p2.r + p2.g + p2.b) / 3.0;
        final grad = (lum2 - lum1).abs();
        if (grad > maxGradBottom && grad > 25) {
          maxGradBottom = grad;
          bestBottomY = y;
        }
      }
      bottomCandidates.add(bestBottomY.toDouble());
    }

    // Sample across vertical positions (20% to 80%) for left and right edges
    for (double f = 0.20; f <= 0.80; f += 0.10) {
      final y = (h * f).round().clamp(0, h - 1);

      // Left edge scan: from 4% inward to 45%
      int bestLeftX = (w * 0.08).round();
      double maxGradLeft = 0;
      for (int x = (w * 0.04).round(); x < (w * 0.45).round(); x += 3) {
        final p1 = decoded.getPixel(x, y);
        final p2 = decoded.getPixel(x + 3, y);
        final lum1 = (p1.r + p1.g + p1.b) / 3.0;
        final lum2 = (p2.r + p2.g + p2.b) / 3.0;
        final grad = (lum2 - lum1).abs();
        if (grad > maxGradLeft && grad > 25) {
          maxGradLeft = grad;
          bestLeftX = x;
        }
      }
      leftCandidates.add(bestLeftX.toDouble());

      // Right edge scan: from 96% inward to 55%
      int bestRightX = (w * 0.92).round();
      double maxGradRight = 0;
      for (int x = (w * 0.96).round(); x > (w * 0.55).round(); x -= 3) {
        final p1 = decoded.getPixel(x, y);
        final p2 = decoded.getPixel(x - 3, y);
        final lum1 = (p1.r + p1.g + p1.b) / 3.0;
        final lum2 = (p2.r + p2.g + p2.b) / 3.0;
        final grad = (lum2 - lum1).abs();
        if (grad > maxGradRight && grad > 25) {
          maxGradRight = grad;
          bestRightX = x;
        }
      }
      rightCandidates.add(bestRightX.toDouble());
    }

    topCandidates.sort();
    bottomCandidates.sort();
    leftCandidates.sort();
    rightCandidates.sort();

    // Take median values to reject outliers from patterned backgrounds
    final medianTop = topCandidates[topCandidates.length ~/ 2];
    final medianBottom = bottomCandidates[bottomCandidates.length ~/ 2];
    final medianLeft = leftCandidates[leftCandidates.length ~/ 2];
    final medianRight = rightCandidates[rightCandidates.length ~/ 2];

    final minX = (medianLeft / w).clamp(0.02, 0.40);
    final maxX = (medianRight / w).clamp(0.60, 0.98);
    final minY = (medianTop / h).clamp(0.02, 0.40);
    final maxY = (medianBottom / h).clamp(0.60, 0.98);

    if (mounted) {
      setState(() {
        _corners = [
          Offset(minX, minY),
          Offset(maxX, minY),
          Offset(maxX, maxY),
          Offset(minX, maxY),
        ];
      });
    }
  }

  Future<bool> _confirmExitWithoutSave() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Cropping?'),
        content: const Text('Do you want to discard your adjusted crop edges?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Editing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return shouldLeave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final leave = await _confirmExitWithoutSave();
          if (leave && mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090D16),
        appBar: AppBar(
          backgroundColor: kNavyPrimary,
          title: Text(widget.pageTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kWhitePure)),
          actions: [
            TextButton.icon(
              onPressed: _detectDocumentEdgesSmart,
              icon: const Icon(Icons.auto_fix_high, color: kBlueLight, size: 18),
              label: const Text('Auto Edge', style: TextStyle(color: kBlueLight)),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _corners = [
                const Offset(0.01, 0.01),
                const Offset(0.99, 0.01),
                const Offset(0.99, 0.99),
                const Offset(0.01, 0.99),
              ]),
              icon: const Icon(Icons.select_all, color: kWhitePure, size: 18),
              label: const Text('Full', style: TextStyle(color: kWhitePure)),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: kNavySecondary,
              child: const Text('Touch & drag any of the 8 pins. A magnifying loupe floats above your thumb.', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boxW = constraints.maxWidth;
                    final boxH = constraints.maxHeight;

                    final topMid = (_corners[0] + _corners[1]) / 2;
                    final rightMid = (_corners[1] + _corners[2]) / 2;
                    final bottomMid = (_corners[2] + _corners[3]) / 2;
                    final leftMid = (_corners[3] + _corners[0]) / 2;

                    final allHandles = [
                      _corners[0],
                      _corners[1],
                      _corners[2],
                      _corners[3],
                      topMid,
                      rightMid,
                      bottomMid,
                      leftMid,
                    ];

                    return GestureDetector(
                      onPanStart: (details) {
                        final local = details.localPosition;
                        final norm = Offset((local.dx / boxW).clamp(0.0, 1.0), (local.dy / boxH).clamp(0.0, 1.0));
                        int closestIdx = 0;
                        double minDist = 999;
                        for (int i = 0; i < allHandles.length; i++) {
                          final d = (norm - allHandles[i]).distance;
                          if (d < minDist) {
                            minDist = d;
                            closestIdx = i;
                          }
                        }
                        if (minDist < 0.20) {
                          setState(() {
                            _activeDragIndex = closestIdx;
                            _activeDragPixelPos = local;
                          });
                        }
                      },
                      onPanUpdate: (details) {
                        if (_activeDragIndex == null) return;
                        final dNorm = Offset(details.delta.dx / boxW, details.delta.dy / boxH);

                        setState(() {
                          _activeDragPixelPos = details.localPosition;
                          if (_activeDragIndex! < 4) {
                            final current = _corners[_activeDragIndex!];
                            _corners[_activeDragIndex!] = Offset((current.dx + dNorm.dx).clamp(0.0, 1.0), (current.dy + dNorm.dy).clamp(0.0, 1.0));
                          } else if (_activeDragIndex == 4) {
                            _corners[0] = Offset(_corners[0].dx, (_corners[0].dy + dNorm.dy).clamp(0.0, 1.0));
                            _corners[1] = Offset(_corners[1].dx, (_corners[1].dy + dNorm.dy).clamp(0.0, 1.0));
                          } else if (_activeDragIndex == 5) {
                            _corners[1] = Offset((_corners[1].dx + dNorm.dx).clamp(0.0, 1.0), _corners[1].dy);
                            _corners[2] = Offset((_corners[2].dx + dNorm.dx).clamp(0.0, 1.0), _corners[2].dy);
                          } else if (_activeDragIndex == 6) {
                            _corners[2] = Offset(_corners[2].dx, (_corners[2].dy + dNorm.dy).clamp(0.0, 1.0));
                            _corners[3] = Offset(_corners[3].dx, (_corners[3].dy + dNorm.dy).clamp(0.0, 1.0));
                          } else if (_activeDragIndex == 7) {
                            _corners[0] = Offset((_corners[0].dx + dNorm.dx).clamp(0.0, 1.0), _corners[0].dy);
                            _corners[3] = Offset((_corners[3].dx + dNorm.dx).clamp(0.0, 1.0), _corners[3].dy);
                          }
                        });
                      },
                      onPanEnd: (_) => setState(() {
                        _activeDragIndex = null;
                        _activeDragPixelPos = null;
                      }),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(widget.imageBytes, fit: BoxFit.fill),
                          CustomPaint(painter: _EightHandleCropGridPainter(corners: _corners, activeIndex: _activeDragIndex)),
                          if (_activeDragPixelPos != null && _activeDragIndex != null && _decodedUiImage != null)
                            Positioned(
                              left: (_activeDragPixelPos!.dx - 55).clamp(10.0, boxW - 120.0),
                              top: (_activeDragPixelPos!.dy - 120).clamp(10.0, boxH - 120.0),
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: kBlueAccent, width: 3.5),
                                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: CustomPaint(
                                  painter: _CropLoupeMagnifierPainter(
                                    sourceImage: _decodedUiImage!,
                                    normalizedTarget: allHandles[_activeDragIndex!],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: kNavyPrimary,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kWhitePure,
                        side: const BorderSide(color: Colors.white38),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(context, widget.imageBytes),
                      child: const Text('Keep Original'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: kBlueAccent,
                        foregroundColor: kWhitePure,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _processingWarp
                          ? null
                          : () async {
                              setState(() => _processingWarp = true);
                              final coords = [
                                _corners[0].dx, _corners[0].dy,
                                _corners[1].dx, _corners[1].dy,
                                _corners[2].dx, _corners[2].dy,
                                _corners[3].dx, _corners[3].dy,
                              ];
                              final warped = await compute(performPerspectiveWarpInIsolate, IsolateWarpPayload(widget.imageBytes, coords));
                              if (mounted) Navigator.pop(context, warped);
                            },
                      icon: const Icon(Icons.crop_rotate),
                      label: Text(_processingWarp ? 'Applying Crop...' : 'Apply Perspective Crop', style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropLoupeMagnifierPainter extends CustomPainter {
  final ui.Image sourceImage;
  final Offset normalizedTarget;
  _CropLoupeMagnifierPainter({required this.sourceImage, required this.normalizedTarget});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = normalizedTarget.dx * sourceImage.width;
    final cy = normalizedTarget.dy * sourceImage.height;

    const zoom = 4.0;
    final sampleW = (size.width / zoom) * (sourceImage.width / 400.0);
    final sampleH = (size.height / zoom) * (sourceImage.height / 400.0);

    final srcRect = Rect.fromCenter(center: Offset(cx, cy), width: sampleW, height: sampleH);
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

    canvas.drawImageRect(sourceImage, srcRect, dstRect, Paint()..filterQuality = FilterQuality.high);

    final crossPaint = Paint()
      ..color = kBlueAccent
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), crossPaint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), crossPaint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 4, Paint()..color = kWhitePure);
  }

  @override
  bool shouldRepaint(covariant _CropLoupeMagnifierPainter oldDelegate) => true;
}

class _EightHandleCropGridPainter extends CustomPainter {
  final List<Offset> corners;
  final int? activeIndex;
  _EightHandleCropGridPainter({required this.corners, this.activeIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final pts = corners.map((c) => Offset(c.dx * size.width, c.dy * size.height)).toList();
    final polyPath = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)), polyPath),
      Paint()..color = Colors.black.withOpacity(0.55),
    );
    canvas.drawPath(polyPath, Paint()..color = kBlueAccent..style = PaintingStyle.stroke..strokeWidth = 2.8);

    for (int i = 0; i < 4; i++) {
      final isCurrent = activeIndex == i;
      canvas.drawCircle(pts[i], isCurrent ? 16 : 12, Paint()..color = kNavyPrimary);
      canvas.drawCircle(pts[i], isCurrent ? 16 : 12, Paint()..color = kBlueAccent..style = PaintingStyle.stroke..strokeWidth = 3.5);
      canvas.drawCircle(pts[i], 4, Paint()..color = kWhitePure);
    }

    final topMid = (pts[0] + pts[1]) / 2;
    final rightMid = (pts[1] + pts[2]) / 2;
    final bottomMid = (pts[2] + pts[3]) / 2;
    final leftMid = (pts[3] + pts[0]) / 2;

    _drawEdgeMidpointBar(canvas, topMid, isHorizontal: true, isCurrent: activeIndex == 4);
    _drawEdgeMidpointBar(canvas, rightMid, isHorizontal: false, isCurrent: activeIndex == 5);
    _drawEdgeMidpointBar(canvas, bottomMid, isHorizontal: true, isCurrent: activeIndex == 6);
    _drawEdgeMidpointBar(canvas, leftMid, isHorizontal: false, isCurrent: activeIndex == 7);
  }

  void _drawEdgeMidpointBar(Canvas canvas, Offset center, {required bool isHorizontal, required bool isCurrent}) {
    final w = isHorizontal ? 28.0 : 8.0;
    final h = isHorizontal ? 8.0 : 28.0;
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: w, height: h), const Radius.circular(4));
    canvas.drawRRect(r, Paint()..color = isCurrent ? kBlueLight : kBlueAccent);
    canvas.drawRRect(r, Paint()..color = kWhitePure..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _EightHandleCropGridPainter oldDelegate) => true;
}
