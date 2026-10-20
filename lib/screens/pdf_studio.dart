import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/document_models.dart';
import '../services/isolate_processor.dart';
import 'crop_studio.dart';
import 'ocr_editor.dart';

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kNavySecondary = Color(0xFF1E293B);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kBlueLight = Color(0xFFDBEAFE);
const Color kWhitePure = Colors.white;

class AcrobatDocumentStudioScreen extends StatefulWidget {
  final List<EditableDocumentPage> initialPages;
  final String initialTitle;
  final int defaultQuality;
  final OcrLanguageMode ocrLang;
  final Future<void> Function(Uint8List pdfBytes, String fileName) onSaveDocument;

  const AcrobatDocumentStudioScreen({
    super.key,
    required this.initialPages,
    required this.initialTitle,
    required this.defaultQuality,
    required this.ocrLang,
    required this.onSaveDocument,
  });

  @override
  State<AcrobatDocumentStudioScreen> createState() => _AcrobatDocumentStudioScreenState();
}

class _AcrobatDocumentStudioScreenState extends State<AcrobatDocumentStudioScreen> {
  late List<EditableDocumentPage> _pages;
  int _currentIndex = 0;
  late int _quality;
  late TextEditingController _titleCtrl;
  bool _processing = false;

  bool _eyedropperSamplingMode = false;
  Offset? _eyedropperTouchPos;
  Color _sampledPaperColor = const Color(0xFFF5F3EB);
  bool _brushEraserActive = false;
  double _eraserBrushSize = 22.0;
  img.Image? _cachedDecodedCurrentPage;

  int? _selectedOverlayIdx;

  @override
  void initState() {
    super.initState();
    _pages = List.from(widget.initialPages);
    _quality = widget.defaultQuality;
    _titleCtrl = TextEditingController(text: widget.initialTitle);
  }

  EditableDocumentPage get _currentPage => _pages[_currentIndex];

  void _samplePixelColorLive(Offset normPos) {
    _cachedDecodedCurrentPage ??= img.decodeImage(_currentPage.displayBytes);
    final decoded = _cachedDecodedCurrentPage;
    if (decoded == null) return;

    final px = (normPos.dx * decoded.width).round().clamp(0, decoded.width - 1);
    final py = (normPos.dy * decoded.height).round().clamp(0, decoded.height - 1);
    final pixel = decoded.getPixel(px, py);

    setState(() {
      _sampledPaperColor = Color.fromARGB(255, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
    });
  }

  void _showEyedropperConfirmationGate() {
    showModalBottomSheet(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _sampledPaperColor, border: Border.all(color: Colors.black26, width: 2)),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Background Color Sampled', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    Text('#${_sampledPaperColor.value.toRadixString(16).substring(2).toUpperCase()}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _eyedropperSamplingMode = true);
                    },
                    child: const Text('Resample Color'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: kBlueAccent),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _brushEraserActive = true);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Color locked! Paint on page to erase blemishes.')));
                    },
                    child: const Text('Confirm & Use Color'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addOverlayImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await File(picked.path).readAsBytes();
    setState(() {
      _currentPage.overlayImages.add(OverlayImageItem(bytes: bytes));
      _selectedOverlayIdx = _currentPage.overlayImages.length - 1;
    });
  }

  Future<bool> _confirmExitWithoutSave() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text('You have unsaved edits on this document. Do you really want to leave?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Editing')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return shouldLeave ?? false;
  }

  Future<void> _compileAndSaveFinalPdf() async {
    setState(() => _processing = true);

    try {
      final pdf = pw.Document();
      for (int i = 0; i < _pages.length; i++) {
        final pItem = _pages[i];

        Uint8List workingBytes = pItem.displayBytes;
        if (pItem.eraserStrokes.isNotEmpty) {
          final decoded = img.decodeImage(workingBytes);
          if (decoded != null) {
            for (final stroke in pItem.eraserStrokes) {
              final col = img.ColorRgba8(stroke.sampledColor.red, stroke.sampledColor.green, stroke.sampledColor.blue, 255);
              final radius = (stroke.strokeWidth * (decoded.width / 380.0)).round().clamp(4, 90);
              for (final pt in stroke.normalizedPoints) {
                final cx = (pt.dx * decoded.width).round();
                final cy = (pt.dy * decoded.height).round();
                img.fillCircle(decoded, x: cx, y: cy, radius: radius, color: col);
              }
            }
            workingBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
          }
        }

        final compressed = await FlutterImageCompress.compressWithList(
          workingBytes,
          quality: _quality,
          rotate: pItem.rotationQuarterTurns * 90,
        );

        final pageW = PdfPageFormat.a4.width;
        final pageH = PdfPageFormat.a4.height;

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Stack(
              children: [
                pw.Positioned.fill(child: pw.Image(pw.MemoryImage(compressed), fit: pw.BoxFit.fill)),
                ...pItem.overlayImages.map((ov) {
                  return pw.Positioned(
                    left: ov.normalizedPos.dx * pageW,
                    top: ov.normalizedPos.dy * pageH,
                    width: ov.normalizedWidth * pageW,
                    height: ov.normalizedHeight * pageH,
                    child: pw.Image(pw.MemoryImage(ov.bytes), fit: pw.BoxFit.fill),
                  );
                }),
                ...pItem.annotations.map((ann) {
                  return pw.Positioned(
                    left: ann.normalizedPos.dx * pageW,
                    top: ann.normalizedPos.dy * pageH,
                    child: pw.Text(ann.text, style: pw.TextStyle(color: PdfColor.fromInt(ann.color.value), fontSize: ann.fontSize, fontWeight: pw.FontWeight.bold)),
                  );
                }),
              ],
            ),
          ),
        );
      }

      final finalBytes = await pdf.save();
      await widget.onSaveDocument(finalBytes, _titleCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved PDF to Vault!'), backgroundColor: Color(0xFF15803D)));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
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
        backgroundColor: kNavyPrimary,
        appBar: AppBar(
          backgroundColor: kNavyPrimary,
          title: Text('Page ${_currentIndex + 1} of ${_pages.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kWhitePure)),
          actions: [
            IconButton(
              tooltip: 'Overlay Secondary Image',
              icon: const Icon(Icons.add_photo_alternate_outlined, color: kWhitePure),
              onPressed: _addOverlayImage,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_processing) const LinearProgressIndicator(color: kBlueAccent),
            Container(
              color: kNavySecondary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _titleCtrl,
                      style: const TextStyle(color: kWhitePure, fontWeight: FontWeight.bold, fontSize: 14),
                      decoration: const InputDecoration(labelText: 'PDF Document Name', labelStyle: TextStyle(color: kBlueLight, fontSize: 11), isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _eyedropperSamplingMode = true;
                        _brushEraserActive = false;
                        _eyedropperTouchPos = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: _eyedropperSamplingMode ? kBlueAccent : kNavyPrimary, borderRadius: BorderRadius.circular(10), border: Border.all(color: kWhitePure.withOpacity(0.4))),
                      child: Row(
                        children: [
                          Container(width: 18, height: 18, decoration: BoxDecoration(color: _sampledPaperColor, shape: BoxShape.circle, border: Border.all(color: kWhitePure, width: 1.5))),
                          const SizedBox(width: 6),
                          const Icon(Icons.colorize, size: 16, color: kWhitePure),
                          const SizedBox(width: 4),
                          const Text('Eyedropper', style: TextStyle(color: kWhitePure, fontSize: 11.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                physics: (_brushEraserActive || _eyedropperSamplingMode || _selectedOverlayIdx != null) ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (_, pageIdx) {
                  final page = _pages[pageIdx];
                  return InteractiveViewer(
                    panEnabled: !_brushEraserActive && !_eyedropperSamplingMode && _selectedOverlayIdx == null,
                    scaleEnabled: true,
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: AspectRatio(
                          aspectRatio: page.imageWidth / math.max(1, page.imageHeight),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final boxW = constraints.maxWidth;
                              final boxH = constraints.maxHeight;

                              return GestureDetector(
                                onPanStart: (d) {
                                  if (_eyedropperSamplingMode) {
                                    final norm = Offset((d.localPosition.dx / boxW).clamp(0.0, 1.0), (d.localPosition.dy / boxH).clamp(0.0, 1.0));
                                    setState(() => _eyedropperTouchPos = d.localPosition);
                                    _samplePixelColorLive(norm);
                                  } else if (_brushEraserActive) {
                                    final norm = Offset((d.localPosition.dx / boxW).clamp(0.0, 1.0), (d.localPosition.dy / boxH).clamp(0.0, 1.0));
                                    setState(() {
                                      page.eraserStrokes.add(BlemishEraserStroke(normalizedPoints: [norm], sampledColor: _sampledPaperColor, strokeWidth: _eraserBrushSize));
                                    });
                                  }
                                },
                                onPanUpdate: (d) {
                                  if (_eyedropperSamplingMode) {
                                    final norm = Offset((d.localPosition.dx / boxW).clamp(0.0, 1.0), (d.localPosition.dy / boxH).clamp(0.0, 1.0));
                                    setState(() => _eyedropperTouchPos = d.localPosition);
                                    _samplePixelColorLive(norm);
                                  } else if (_brushEraserActive) {
                                    if (page.eraserStrokes.isEmpty) return;
                                    final norm = Offset((d.localPosition.dx / boxW).clamp(0.0, 1.0), (d.localPosition.dy / boxH).clamp(0.0, 1.0));
                                    setState(() => page.eraserStrokes.last.normalizedPoints.add(norm));
                                  }
                                },
                                onPanEnd: (_) {
                                  if (_eyedropperSamplingMode) {
                                    setState(() {
                                      _eyedropperSamplingMode = false;
                                      _eyedropperTouchPos = null;
                                    });
                                    _showEyedropperConfirmationGate();
                                  }
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    RotatedBox(quarterTurns: page.rotationQuarterTurns, child: Image.memory(page.displayBytes, fit: BoxFit.fill)),
                                    CustomPaint(painter: _BlemishEraserCanvasPainter(strokes: page.eraserStrokes)),
                                    ...List.generate(page.overlayImages.length, (ovIdx) {
                                      final ov = page.overlayImages[ovIdx];
                                      final isSel = _selectedOverlayIdx == ovIdx;
                                      return Positioned(
                                        left: ov.normalizedPos.dx * boxW,
                                        top: ov.normalizedPos.dy * boxH,
                                        width: ov.normalizedWidth * boxW,
                                        height: ov.normalizedHeight * boxH,
                                        child: GestureDetector(
                                          onTap: () => setState(() => _selectedOverlayIdx = ovIdx),
                                          onPanUpdate: (d) => setState(() {
                                            ov.normalizedPos = Offset(
                                              (ov.normalizedPos.dx + d.delta.dx / boxW).clamp(0.0, 1.0 - ov.normalizedWidth),
                                              (ov.normalizedPos.dy + d.delta.dy / boxH).clamp(0.0, 1.0 - ov.normalizedHeight),
                                            );
                                          }),
                                          child: Stack(
                                            children: [
                                              Positioned.fill(
                                                child: Container(
                                                  decoration: isSel ? BoxDecoration(border: Border.all(color: kBlueAccent, width: 2.0)) : null,
                                                  child: Image.memory(ov.bytes, fit: BoxFit.fill),
                                                ),
                                              ),
                                              if (isSel)
                                                Positioned(
                                                  right: 0,
                                                  bottom: 0,
                                                  child: GestureDetector(
                                                    onPanUpdate: (sd) => setState(() {
                                                      ov.normalizedWidth = (ov.normalizedWidth + sd.delta.dx / boxW).clamp(0.10, 0.90);
                                                      ov.normalizedHeight = (ov.normalizedHeight + sd.delta.dy / boxH).clamp(0.05, 0.90);
                                                    }),
                                                    child: Container(
                                                      width: 24,
                                                      height: 24,
                                                      color: kBlueAccent,
                                                      child: const Icon(Icons.open_in_full, size: 14, color: kWhitePure),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                    if (_eyedropperSamplingMode && _eyedropperTouchPos != null)
                                      Positioned(
                                        left: (_eyedropperTouchPos!.dx - 40).clamp(10.0, boxW - 90.0),
                                        top: (_eyedropperTouchPos!.dy - 90).clamp(10.0, boxH - 90.0),
                                        child: Container(
                                          width: 80,
                                          height: 80,
                                          decoration: BoxDecoration(shape: BoxShape.circle, color: _sampledPaperColor, border: Border.all(color: kWhitePure, width: 4), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))]),
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Container(width: 1, height: 32, color: kNavyPrimary.withOpacity(0.6)),
                                              Container(width: 32, height: 1, color: kNavyPrimary.withOpacity(0.6)),
                                            ],
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
                    ),
                  );
                },
              ),
            ),
            Container(
              color: kNavyPrimary,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Slider(value: _quality.toDouble(), min: 20, max: 100, divisions: 8, activeColor: kBlueAccent, onChanged: (v) => setState(() => _quality = v.round())),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kBlueAccent, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                    onPressed: _processing ? null : _compileAndSaveFinalPdf,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Save PDF', style: TextStyle(fontWeight: FontWeight.w900)),
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

class _BlemishEraserCanvasPainter extends CustomPainter {
  final List<BlemishEraserStroke> strokes;
  _BlemishEraserCanvasPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.sampledColor
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.strokeWidth;

      if (s.normalizedPoints.length == 1) {
        final pt = Offset(s.normalizedPoints.first.dx * size.width, s.normalizedPoints.first.dy * size.height);
        canvas.drawCircle(pt, s.strokeWidth / 2, Paint()..color = s.sampledColor);
      } else {
        final path = Path();
        for (int i = 0; i < s.normalizedPoints.length; i++) {
          final pt = Offset(s.normalizedPoints[i].dx * size.width, s.normalizedPoints[i].dy * size.height);
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BlemishEraserCanvasPainter oldDelegate) => true;
}
