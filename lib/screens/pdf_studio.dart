import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
const Color kStudioLightBg = Color(0xFFF8FAFC);
const Color kBorderSubtle = Color(0xFFE2E8F0);
const Color kSlateMuted = Color(0xFF64748B);

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

  final TransformationController _transCtrl = TransformationController();

  // Eyedropper & Eraser
  bool _eyedropperSamplingMode = false;
  Offset? _eyedropperTouchPos;
  Color _sampledPaperColor = const Color(0xFFF5F3EB);
  bool _brushEraserActive = false;
  double _eraserBrushSize = 22.0;
  img.Image? _cachedDecodedCurrentPage;

  // Active Selections
  int? _selectedOverlayIdx;
  int? _selectedAnnotationIdx;

  // Permanent Signature Cache
  Uint8List? _savedPermanentSignature;

  @override
  void initState() {
    super.initState();
    _pages = List.from(widget.initialPages);
    _quality = widget.defaultQuality;
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _loadPermanentSignature();
  }

  @override
  void dispose() {
    _transCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  EditableDocumentPage get _currentPage => _pages[_currentIndex];

  Future<File> _getPermanentSignatureFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'permanent_signature.png'));
  }

  Future<void> _loadPermanentSignature() async {
    try {
      final file = await _getPermanentSignatureFile();
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty && mounted) {
          setState(() => _savedPermanentSignature = bytes);
        }
      }
    } catch (_) {}
  }

  Future<void> _savePermanentSignature(Uint8List bytes) async {
    try {
      final file = await _getPermanentSignatureFile();
      await file.writeAsBytes(bytes, flush: true);
      if (mounted) {
        setState(() => _savedPermanentSignature = bytes);
      }
    } catch (_) {}
  }

  Future<void> _deletePermanentSignature() async {
    try {
      final file = await _getPermanentSignatureFile();
      if (await file.exists()) {
        await file.delete();
      }
      if (mounted) {
        setState(() => _savedPermanentSignature = null);
      }
    } catch (_) {}
  }

  Future<void> _applyFilterFastIsolate(ScanColorFilter filter) async {
    final page = _currentPage;
    if (filter == ScanColorFilter.original) {
      setState(() {
        page.activeFilter = filter;
        page.displayBytes = page.originalBytes;
        _cachedDecodedCurrentPage = null;
      });
      return;
    }

    setState(() => _processing = true);
    final result = await compute(
      applyFilterInBackgroundIsolate,
      IsolateFilterPayload(page.originalBytes, filter.index),
    );
    if (mounted) {
      setState(() {
        page.activeFilter = filter;
        page.displayBytes = result;
        _cachedDecodedCurrentPage = null;
        _processing = false;
      });
    }
  }

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
      backgroundColor: kWhitePure,
      barrierColor: Colors.black26,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _sampledPaperColor,
                    border: Border.all(color: Colors.black26, width: 2),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Background Color Sampled',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kNavyPrimary),
                    ),
                    Text(
                      '#${_sampledPaperColor.value.toRadixString(16).substring(2).toUpperCase()}',
                      style: const TextStyle(fontSize: 12, color: kSlateMuted),
                    ),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Color locked! Paint on page to erase blemishes.')),
                      );
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
      _selectedAnnotationIdx = null;
    });
  }

  Future<void> _showTextEditorDialog({PageAnnotationItem? existingItem, int? index}) async {
    final txtCtrl = TextEditingController(text: existingItem?.text ?? '');
    double chosenSize = existingItem?.fontSize ?? 22.0;
    Color chosenColor = existingItem?.color ?? kNavyPrimary;

    final List<Color> palette = [
      kNavyPrimary,
      kBlueAccent,
      const Color(0xFFDC2626),
      const Color(0xFF15803D),
      const Color(0xFF7C3AED),
      Colors.black,
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          backgroundColor: kWhitePure,
          title: Text(
            existingItem == null ? 'Add Text on Page' : 'Edit Selected Text',
            style: const TextStyle(fontWeight: FontWeight.w900, color: kNavyPrimary),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: txtCtrl,
                  autofocus: true,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Enter Document Text',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Font Size:', style: TextStyle(fontWeight: FontWeight.bold, color: kNavyPrimary)),
                    Text(
                      '${chosenSize.round()} pt',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: kBlueAccent),
                    ),
                  ],
                ),
                Slider(
                  value: chosenSize.clamp(8.0, 96.0),
                  min: 8,
                  max: 96,
                  activeColor: kBlueAccent,
                  onChanged: (v) => setModal(() => chosenSize = v),
                ),
                const SizedBox(height: 8),
                const Text('Ink Color:', style: TextStyle(fontWeight: FontWeight.bold, color: kNavyPrimary, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: palette.map((c) {
                    final isPicked = chosenColor.value == c.value;
                    return GestureDetector(
                      onTap: () => setModal(() => chosenColor = c),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isPicked ? kBlueAccent : Colors.black26,
                            width: isPicked ? 3.0 : 1.0,
                          ),
                        ),
                        child: isPicked ? const Icon(Icons.check, size: 16, color: kWhitePure) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            if (existingItem != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () {
                  setState(() {
                    if (index != null && index < _currentPage.annotations.length) {
                      _currentPage.annotations.removeAt(index);
                      _selectedAnnotationIdx = null;
                    }
                  });
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kBlueAccent),
              onPressed: () {
                final trimmed = txtCtrl.text.trim();
                if (trimmed.isNotEmpty) {
                  setState(() {
                    if (existingItem != null && index != null) {
                      existingItem.text = trimmed;
                      existingItem.fontSize = chosenSize;
                      existingItem.color = chosenColor;
                      _selectedAnnotationIdx = index;
                    } else {
                      _currentPage.annotations.add(
                        PageAnnotationItem(
                          type: 'text',
                          text: trimmed,
                          fontSize: chosenSize,
                          color: chosenColor,
                          normalizedPos: const Offset(0.32, 0.38),
                        ),
                      );
                      _selectedAnnotationIdx = _currentPage.annotations.length - 1;
                      _selectedOverlayIdx = null;
                    }
                  });
                }
                Navigator.pop(ctx);
              },
              child: Text(existingItem == null ? 'Place Text' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _stampSignatureOnPage(Uint8List sigBytes) {
    setState(() {
      _currentPage.annotations.add(
        PageAnnotationItem(
          type: 'signature',
          normalizedPos: const Offset(0.52, 0.72),
          signaturePng: sigBytes,
          fontSize: 48.0, // Used as base height for scalable signature
        ),
      );
      _selectedAnnotationIdx = _currentPage.annotations.length - 1;
      _selectedOverlayIdx = null;
    });
  }

  Future<void> _openSignatureHubModal() async {
    await _loadPermanentSignature();
    if (!mounted) return;

    if (_savedPermanentSignature == null) {
      await _openDrawSignaturePad(saveAsPermanentDefault: true);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: kWhitePure,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Signature Studio',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kNavyPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Stamp your saved permanent signature or draw a new one.',
              style: TextStyle(fontSize: 12.5, color: kSlateMuted),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              height: 90,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kStudioLightBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorderSubtle),
              ),
              child: Center(
                child: Image.memory(_savedPermanentSignature!, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kBlueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _stampSignatureOnPage(_savedPermanentSignature!);
                },
                icon: const Icon(Icons.verified_outlined, size: 20),
                label: const Text(
                  'Stamp Saved Signature on Page',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openDrawSignaturePad(saveAsPermanentDefault: false);
                    },
                    icon: const Icon(Icons.gesture, size: 18),
                    label: const Text('Draw One-Time'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openDrawSignaturePad(saveAsPermanentDefault: true);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Replace Saved'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () async {
                  await _deletePermanentSignature();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Removed saved permanent signature.')),
                    );
                  }
                },
                icon: const Icon(Icons.delete_outline, size: 17),
                label: const Text('Delete Permanent Signature', style: TextStyle(fontSize: 12.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDrawSignaturePad({required bool saveAsPermanentDefault}) async {
    final List<Offset?> points = [];
    bool savePermanent = saveAsPermanentDefault;

    final sigBytes = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kWhitePure,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          height: 410,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Draw Ink Signature',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: kNavyPrimary),
                  ),
                  TextButton(
                    onPressed: () => setModal(() => points.clear()),
                    child: const Text('Clear Pad'),
                  ),
                ],
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: kStudioLightBg,
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: GestureDetector(
                    onPanUpdate: (d) => setModal(() => points.add(d.localPosition)),
                    onPanEnd: (_) => setModal(() => points.add(null)),
                    child: CustomPaint(
                      painter: _InkSignaturePainter(points: points),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeColor: kBlueAccent,
                value: savePermanent,
                onChanged: (v) => setModal(() => savePermanent = v ?? true),
                title: const Text(
                  'Save as my permanent signature for future documents',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kNavyPrimary),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: kBlueAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    if (points.whereType<Offset>().isEmpty) return;
                    final recorder = ui.PictureRecorder();
                    final canvas = Canvas(recorder);
                    _InkSignaturePainter(points: points).paint(canvas, const Size(420, 180));
                    final pic = recorder.endRecording();
                    final uiImg = await pic.toImage(420, 180);
                    final byteData = await uiImg.toByteData(format: ui.ImageByteFormat.png);
                    final pngBytes = byteData?.buffer.asUint8List();
                    if (pngBytes != null && savePermanent) {
                      await _savePermanentSignature(pngBytes);
                    }
                    if (ctx.mounted) Navigator.pop(ctx, pngBytes);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text(
                    'Place Signature on Page',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (sigBytes != null) {
      _stampSignatureOnPage(sigBytes);
    }
  }

  Future<bool> _confirmExitWithoutSave() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kWhitePure,
        title: const Text('Discard Changes?', style: TextStyle(fontWeight: FontWeight.bold, color: kNavyPrimary)),
        content: const Text('You have unsaved edits on this document. Do you really want to leave?'),
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
              final col = img.ColorRgba8(
                stroke.sampledColor.red,
                stroke.sampledColor.green,
                stroke.sampledColor.blue,
                255,
              );
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
                pw.Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: pw.Image(pw.MemoryImage(compressed), fit: pw.BoxFit.fill),
                ),
                ...pItem.overlayImages.map((ov) {
                  return pw.Positioned(
                    left: ov.normalizedPos.dx * pageW,
                    top: ov.normalizedPos.dy * pageH,
                    child: pw.SizedBox(
                      width: ov.normalizedWidth * pageW,
                      height: ov.normalizedHeight * pageH,
                      child: pw.Image(pw.MemoryImage(ov.bytes), fit: pw.BoxFit.fill),
                    ),
                  );
                }),
                ...pItem.annotations.map((ann) {
                  if (ann.type == 'signature' && ann.signaturePng != null) {
                    final double sigH = ann.fontSize.clamp(24.0, 160.0);
                    final double sigW = sigH * 2.2;
                    return pw.Positioned(
                      left: ann.normalizedPos.dx * pageW,
                      top: ann.normalizedPos.dy * pageH,
                      child: pw.SizedBox(
                        width: sigW,
                        height: sigH,
                        child: pw.Image(pw.MemoryImage(ann.signaturePng!), fit: pw.BoxFit.contain),
                      ),
                    );
                  }
                  return pw.Positioned(
                    left: ann.normalizedPos.dx * pageW,
                    top: ann.normalizedPos.dy * pageH,
                    child: pw.Text(
                      ann.text,
                      style: pw.TextStyle(
                        color: PdfColor.fromInt(ann.color.value),
                        fontSize: ann.fontSize,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved PDF to Vault!'),
            backgroundColor: Color(0xFF15803D),
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool drawingModeActive = _eyedropperSamplingMode || _brushEraserActive;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final leave = await _confirmExitWithoutSave();
          if (leave && mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: kStudioLightBg,
        appBar: AppBar(
          backgroundColor: kWhitePure,
          foregroundColor: kNavyPrimary,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          shape: const Border(bottom: BorderSide(color: kBorderSubtle)),
          title: Text(
            'Page ${_currentIndex + 1} of ${_pages.length}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kNavyPrimary),
          ),
          actions: [
            IconButton(
              tooltip: 'Zoom In',
              icon: const Icon(Icons.zoom_in_rounded, color: kNavyPrimary),
              onPressed: () {
                final currentScale = _transCtrl.value.getMaxScaleOnAxis();
                final nextScale = (currentScale * 1.35).clamp(1.0, 8.0);
                setState(() {
                  _transCtrl.value = Matrix4.identity()..scale(nextScale);
                });
              },
            ),
            IconButton(
              tooltip: 'Reset Zoom (1x)',
              icon: const Icon(Icons.restart_alt_rounded, color: kNavyPrimary),
              onPressed: () => setState(() => _transCtrl.value = Matrix4.identity()),
            ),
            IconButton(
              tooltip: 'Overlay Secondary Image',
              icon: const Icon(Icons.add_photo_alternate_outlined, color: kBlueAccent),
              onPressed: _addOverlayImage,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_processing) const LinearProgressIndicator(color: kBlueAccent),
            // White Executive Header Bar
            Container(
              decoration: const BoxDecoration(
                color: kWhitePure,
                border: Border(bottom: BorderSide(color: kBorderSubtle)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _titleCtrl,
                      style: const TextStyle(color: kNavyPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'PDF Document Name',
                        labelStyle: const TextStyle(color: kBlueAccent, fontSize: 11, fontWeight: FontWeight.w600),
                        isDense: true,
                        filled: true,
                        fillColor: kStudioLightBg,
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: kBorderSubtle),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: kBlueAccent, width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _eyedropperSamplingMode = !_eyedropperSamplingMode;
                        _brushEraserActive = false;
                        _eyedropperTouchPos = null;
                        _selectedAnnotationIdx = null;
                        _selectedOverlayIdx = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: _eyedropperSamplingMode ? kBlueAccent : kStudioLightBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _eyedropperSamplingMode ? kBlueAccent : kBorderSubtle,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: _sampledPaperColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black26, width: 1.5),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.colorize,
                            size: 16,
                            color: _eyedropperSamplingMode ? kWhitePure : kBlueAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Eyedropper',
                            style: TextStyle(
                              color: _eyedropperSamplingMode ? kWhitePure : kNavyPrimary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_brushEraserActive)
              Container(
                decoration: const BoxDecoration(
                  color: kBlueLight,
                  border: Border(bottom: BorderSide(color: kBorderSubtle)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  children: [
                    const Text(
                      'Eraser Size:',
                      style: TextStyle(color: kNavyPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Slider(
                        value: _eraserBrushSize,
                        min: 8,
                        max: 60,
                        activeColor: kBlueAccent,
                        onChanged: (v) => setState(() => _eraserBrushSize = v),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Undo Eraser Stroke',
                      icon: const Icon(Icons.undo, color: kNavyPrimary, size: 18),
                      onPressed: _currentPage.eraserStrokes.isEmpty
                          ? null
                          : () => setState(() => _currentPage.eraserStrokes.removeLast()),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _brushEraserActive = false),
                      child: const Text(
                        'Done',
                        style: TextStyle(color: kBlueAccent, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            // Main White Studio Workspace with Unblocked Pinch-to-Zoom
            Expanded(
              child: PageView.builder(
                physics: (drawingModeActive || _selectedOverlayIdx != null || _selectedAnnotationIdx != null)
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() {
                  _currentIndex = i;
                  _selectedAnnotationIdx = null;
                  _selectedOverlayIdx = null;
                  _transCtrl.value = Matrix4.identity();
                }),
                itemBuilder: (_, pageIdx) {
                  final page = _pages[pageIdx];
                  return InteractiveViewer(
                    transformationController: _transCtrl,
                    minScale: 1.0,
                    maxScale: 8.0,
                    panEnabled: !drawingModeActive,
                    scaleEnabled: true,
                    boundaryMargin: const EdgeInsets.all(80),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Container(
                          decoration: BoxDecoration(
                            color: kWhitePure,
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 16,
                                offset: Offset(0, 6),
                              ),
                            ],
                            border: Border.all(color: kBorderSubtle),
                          ),
                          child: AspectRatio(
                            aspectRatio: page.imageWidth / math.max(1, page.imageHeight),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final boxW = constraints.maxWidth;
                                final boxH = constraints.maxHeight;

                                return GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () {
                                    if (_selectedAnnotationIdx != null || _selectedOverlayIdx != null) {
                                      setState(() {
                                        _selectedAnnotationIdx = null;
                                        _selectedOverlayIdx = null;
                                      });
                                    }
                                  },
                                  onPanStart: drawingModeActive
                                      ? (d) {
                                          final norm = Offset(
                                            (d.localPosition.dx / boxW).clamp(0.0, 1.0),
                                            (d.localPosition.dy / boxH).clamp(0.0, 1.0),
                                          );
                                          if (_eyedropperSamplingMode) {
                                            setState(() => _eyedropperTouchPos = d.localPosition);
                                            _samplePixelColorLive(norm);
                                          } else if (_brushEraserActive) {
                                            setState(() {
                                              page.eraserStrokes.add(
                                                BlemishEraserStroke(
                                                  normalizedPoints: [norm],
                                                  sampledColor: _sampledPaperColor,
                                                  strokeWidth: _eraserBrushSize,
                                                ),
                                              );
                                            });
                                          }
                                        }
                                      : null,
                                  onPanUpdate: drawingModeActive
                                      ? (d) {
                                          final norm = Offset(
                                            (d.localPosition.dx / boxW).clamp(0.0, 1.0),
                                            (d.localPosition.dy / boxH).clamp(0.0, 1.0),
                                          );
                                          if (_eyedropperSamplingMode) {
                                            setState(() => _eyedropperTouchPos = d.localPosition);
                                            _samplePixelColorLive(norm);
                                          } else if (_brushEraserActive) {
                                            if (page.eraserStrokes.isEmpty) return;
                                            setState(() => page.eraserStrokes.last.normalizedPoints.add(norm));
                                          }
                                        }
                                      : null,
                                  onPanEnd: drawingModeActive
                                      ? (_) {
                                          if (_eyedropperSamplingMode) {
                                            setState(() {
                                              _eyedropperSamplingMode = false;
                                              _eyedropperTouchPos = null;
                                            });
                                            _showEyedropperConfirmationGate();
                                          }
                                        }
                                      : null,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    clipBehavior: Clip.none,
                                    children: [
                                      RotatedBox(
                                        quarterTurns: page.rotationQuarterTurns,
                                        child: Image.memory(page.displayBytes, fit: BoxFit.fill),
                                      ),
                                      CustomPaint(painter: _BlemishEraserCanvasPainter(strokes: page.eraserStrokes)),
                                      // Secondary Image Overlays
                                      ...List.generate(page.overlayImages.length, (ovIdx) {
                                        final ov = page.overlayImages[ovIdx];
                                        final isSel = _selectedOverlayIdx == ovIdx;
                                        return Positioned(
                                          left: ov.normalizedPos.dx * boxW,
                                          top: ov.normalizedPos.dy * boxH,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => setState(() {
                                              _selectedOverlayIdx = ovIdx;
                                              _selectedAnnotationIdx = null;
                                            }),
                                            onPanUpdate: (d) => setState(() {
                                              ov.normalizedPos = Offset(
                                                (ov.normalizedPos.dx + d.delta.dx / boxW).clamp(0.0, 1.0 - ov.normalizedWidth),
                                                (ov.normalizedPos.dy + d.delta.dy / boxH).clamp(0.0, 1.0 - ov.normalizedHeight),
                                              );
                                            }),
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Container(
                                                  width: ov.normalizedWidth * boxW,
                                                  height: ov.normalizedHeight * boxH,
                                                  decoration: isSel
                                                      ? BoxDecoration(
                                                          border: Border.all(color: kBlueAccent, width: 2.0),
                                                        )
                                                      : null,
                                                  child: Image.memory(ov.bytes, fit: BoxFit.fill),
                                                ),
                                                if (isSel) ...[
                                                  Positioned(
                                                    right: -12,
                                                    bottom: -12,
                                                    child: GestureDetector(
                                                      behavior: HitTestBehavior.opaque,
                                                      onPanUpdate: (sd) => setState(() {
                                                        ov.normalizedWidth = (ov.normalizedWidth + sd.delta.dx / boxW).clamp(0.08, 0.95);
                                                        ov.normalizedHeight = (ov.normalizedHeight + sd.delta.dy / boxH).clamp(0.05, 0.95);
                                                      }),
                                                      child: Container(
                                                        width: 28,
                                                        height: 28,
                                                        decoration: const BoxDecoration(
                                                          color: kBlueAccent,
                                                          shape: BoxShape.circle,
                                                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                                        ),
                                                        child: const Icon(Icons.open_in_full, size: 15, color: kWhitePure),
                                                      ),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    right: -12,
                                                    top: -12,
                                                    child: GestureDetector(
                                                      behavior: HitTestBehavior.opaque,
                                                      onTap: () => setState(() {
                                                        page.overlayImages.removeAt(ovIdx);
                                                        _selectedOverlayIdx = null;
                                                      }),
                                                      child: Container(
                                                        width: 28,
                                                        height: 28,
                                                        decoration: const BoxDecoration(
                                                          color: Colors.red,
                                                          shape: BoxShape.circle,
                                                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                                        ),
                                                        child: const Icon(Icons.delete_outline, size: 15, color: kWhitePure),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                      // Interactive Text & Signature Layers with Enlarge / Edit / Delete Handles
                                      ...List.generate(page.annotations.length, (annIdx) {
                                        final ann = page.annotations[annIdx];
                                        final isSelected = _selectedAnnotationIdx == annIdx;
                                        final bool isSignature = ann.type == 'signature' && ann.signaturePng != null;
                                        final double sigHeight = ann.fontSize.clamp(24.0, 160.0);
                                        final double sigWidth = sigHeight * 2.2;

                                        return Positioned(
                                          left: ann.normalizedPos.dx * boxW,
                                          top: ann.normalizedPos.dy * boxH,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => setState(() {
                                              _selectedAnnotationIdx = annIdx;
                                              _selectedOverlayIdx = null;
                                            }),
                                            onDoubleTap: () {
                                              if (!isSignature) {
                                                _showTextEditorDialog(existingItem: ann, index: annIdx);
                                              }
                                            },
                                            onPanUpdate: (d) => setState(() {
                                              _selectedAnnotationIdx = annIdx;
                                              ann.normalizedPos = Offset(
                                                (ann.normalizedPos.dx + d.delta.dx / boxW).clamp(0.01, 0.94),
                                                (ann.normalizedPos.dy + d.delta.dy / boxH).clamp(0.01, 0.94),
                                              );
                                            }),
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Container(
                                                  margin: const EdgeInsets.all(14),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: isSelected
                                                      ? BoxDecoration(
                                                          color: kBlueAccent.withOpacity(0.10),
                                                          border: Border.all(color: kBlueAccent, width: 1.8),
                                                          borderRadius: BorderRadius.circular(6),
                                                        )
                                                      : BoxDecoration(
                                                          border: Border.all(color: Colors.transparent, width: 1.8),
                                                        ),
                                                  child: isSignature
                                                      ? Image.memory(
                                                          ann.signaturePng!,
                                                          width: sigWidth,
                                                          height: sigHeight,
                                                          fit: BoxFit.contain,
                                                        )
                                                      : Text(
                                                          ann.text,
                                                          style: TextStyle(
                                                            color: ann.color,
                                                            fontSize: ann.fontSize,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                ),
                                                if (isSelected) ...[
                                                  // Top-Left: Edit Text Wording (Pencil)
                                                  if (!isSignature)
                                                    Positioned(
                                                      left: 0,
                                                      top: 0,
                                                      child: GestureDetector(
                                                        behavior: HitTestBehavior.opaque,
                                                        onTap: () => _showTextEditorDialog(existingItem: ann, index: annIdx),
                                                        child: Container(
                                                          width: 28,
                                                          height: 28,
                                                          decoration: const BoxDecoration(
                                                            color: kBlueAccent,
                                                            shape: BoxShape.circle,
                                                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                                          ),
                                                          child: const Icon(Icons.edit, size: 15, color: kWhitePure),
                                                        ),
                                                      ),
                                                    ),
                                                  // Top-Right: Delete / Remove Item (Trash)
                                                  Positioned(
                                                    right: 0,
                                                    top: 0,
                                                    child: GestureDetector(
                                                      behavior: HitTestBehavior.opaque,
                                                      onTap: () => setState(() {
                                                        page.annotations.removeAt(annIdx);
                                                        _selectedAnnotationIdx = null;
                                                      }),
                                                      child: Container(
                                                        width: 28,
                                                        height: 28,
                                                        decoration: const BoxDecoration(
                                                          color: Colors.red,
                                                          shape: BoxShape.circle,
                                                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                                        ),
                                                        child: const Icon(Icons.delete_outline, size: 15, color: kWhitePure),
                                                      ),
                                                    ),
                                                  ),
                                                  // Bottom-Right: Drag to Enlarge / Shrink Size
                                                  Positioned(
                                                    right: 0,
                                                    bottom: 0,
                                                    child: GestureDetector(
                                                      behavior: HitTestBehavior.opaque,
                                                      onPanUpdate: (sd) => setState(() {
                                                        final deltaChange = (sd.delta.dx + sd.delta.dy) * 0.35;
                                                        ann.fontSize = (ann.fontSize + deltaChange).clamp(8.0, 120.0);
                                                      }),
                                                      child: Container(
                                                        width: 28,
                                                        height: 28,
                                                        decoration: const BoxDecoration(
                                                          color: Color(0xFF15803D),
                                                          shape: BoxShape.circle,
                                                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                                        ),
                                                        child: const Icon(Icons.open_in_full, size: 15, color: kWhitePure),
                                                      ),
                                                    ),
                                                  ),
                                                ],
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
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: _sampledPaperColor,
                                              border: Border.all(color: kWhitePure, width: 4),
                                              boxShadow: const [
                                                BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                                              ],
                                            ),
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
                    ),
                  );
                },
              ),
            ),
            // Quick Size Adjustment Bar When Any Text or Signature Is Selected
            if (_selectedAnnotationIdx != null && _selectedAnnotationIdx! < _currentPage.annotations.length)
              Container(
                decoration: const BoxDecoration(
                  color: kWhitePure,
                  border: Border(top: BorderSide(color: kBorderSubtle)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Builder(
                  builder: (context) {
                    final selAnn = _currentPage.annotations[_selectedAnnotationIdx!];
                    final isSig = selAnn.type == 'signature';
                    return Row(
                      children: [
                        Icon(isSig ? Icons.draw_outlined : Icons.format_size, size: 18, color: kBlueAccent),
                        const SizedBox(width: 8),
                        Text(
                          isSig ? 'Signature Scale:' : 'Text Size:',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kNavyPrimary),
                        ),
                        Expanded(
                          child: Slider(
                            value: selAnn.fontSize.clamp(8.0, 120.0),
                            min: 8.0,
                            max: 120.0,
                            activeColor: kBlueAccent,
                            onChanged: (v) => setState(() => selAnn.fontSize = v),
                          ),
                        ),
                        if (!isSig)
                          IconButton(
                            tooltip: 'Edit Wording',
                            icon: const Icon(Icons.edit_outlined, size: 20, color: kBlueAccent),
                            onPressed: () => _showTextEditorDialog(existingItem: selAnn, index: _selectedAnnotationIdx!),
                          ),
                        IconButton(
                          tooltip: 'Delete Selected',
                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                          onPressed: () => setState(() {
                            _currentPage.annotations.removeAt(_selectedAnnotationIdx!);
                            _selectedAnnotationIdx = null;
                          }),
                        ),
                      ],
                    );
                  },
                ),
              ),
            // White Filter Strip
            Container(
              height: 46,
              decoration: const BoxDecoration(
                color: kWhitePure,
                border: Border(top: BorderSide(color: kBorderSubtle)),
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: ScanColorFilter.values.map((f) {
                  final selected = _currentPage.activeFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        f.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                          color: selected ? kBlueAccent : kNavyPrimary,
                        ),
                      ),
                      selected: selected,
                      backgroundColor: kStudioLightBg,
                      selectedColor: kBlueLight,
                      side: BorderSide(color: selected ? kBlueAccent : kBorderSubtle),
                      onSelected: (_) => _applyFilterFastIsolate(f),
                    ),
                  );
                }).toList(),
              ),
            ),
            // White Executive Bottom Toolbar
            Container(
              decoration: const BoxDecoration(
                color: kWhitePure,
                border: Border(top: BorderSide(color: kBorderSubtle)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _studioActionBtn(
                          icon: Icons.text_fields_rounded,
                          label: 'Add Text',
                          onTap: () => _showTextEditorDialog(),
                        ),
                        _studioActionBtn(
                          icon: Icons.draw_outlined,
                          label: _savedPermanentSignature != null ? 'Sign (Saved)' : 'Sign Ink',
                          onTap: _openSignatureHubModal,
                        ),
                        _studioActionBtn(
                          icon: Icons.crop_free,
                          label: '8-Handle Crop',
                          onTap: () async {
                            final warped = await Navigator.push<Uint8List>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EightHandlePerspectiveCropScreen(
                                  imageBytes: _currentPage.originalBytes,
                                  pageTitle: '8-Handle Perspective Crop',
                                ),
                              ),
                            );
                            if (warped != null) {
                              setState(() {
                                _currentPage.originalBytes = warped;
                                _currentPage.displayBytes = warped;
                                _cachedDecodedCurrentPage = null;
                              });
                            }
                          },
                        ),
                        _studioActionBtn(
                          icon: Icons.brush_outlined,
                          label: _brushEraserActive ? 'Eraser ON' : 'Color Eraser',
                          isActive: _brushEraserActive,
                          onTap: () => setState(() {
                            _brushEraserActive = !_brushEraserActive;
                            _selectedAnnotationIdx = null;
                            _selectedOverlayIdx = null;
                          }),
                        ),
                        _studioActionBtn(
                          icon: Icons.manage_search_rounded,
                          label: 'OCR & Search',
                          onTap: () async {
                            final updatedBytes = await Navigator.push<Uint8List>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => InPlaceSelectableOcrScreen(
                                  imageBytes: _currentPage.displayBytes,
                                  imageWidth: _currentPage.imageWidth,
                                  imageHeight: _currentPage.imageHeight,
                                  initialLang: widget.ocrLang,
                                  onOcrCompleted: (words) => _currentPage.ocrWords = words,
                                ),
                              ),
                            );
                            if (updatedBytes != null && mounted) {
                              setState(() {
                                _currentPage.displayBytes = updatedBytes;
                                _cachedDecodedCurrentPage = null;
                              });
                            }
                          },
                        ),
                        _studioActionBtn(
                          icon: Icons.rotate_right,
                          label: 'Rotate 90°',
                          onTap: () => setState(() {
                            _currentPage.rotationQuarterTurns = (_currentPage.rotationQuarterTurns + 1) % 4;
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        'Quality:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kSlateMuted),
                      ),
                      Expanded(
                        child: Slider(
                          value: _quality.toDouble(),
                          min: 20,
                          max: 100,
                          divisions: 8,
                          activeColor: kBlueAccent,
                          label: '$_quality%',
                          onChanged: (v) => setState(() => _quality = v.round()),
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kBlueAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                        onPressed: _processing ? null : _compileAndSaveFinalPdf,
                        icon: const Icon(Icons.save_alt, size: 18),
                        label: const Text('Save PDF', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _studioActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: isActive ? kBlueAccent : kStudioLightBg,
          foregroundColor: isActive ? kWhitePure : kNavyPrimary,
          side: BorderSide(color: isActive ? kBlueAccent : kBorderSubtle),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 17, color: isActive ? kWhitePure : kBlueAccent),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? kWhitePure : kNavyPrimary,
          ),
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

class _InkSignaturePainter extends CustomPainter {
  final List<Offset?> points;
  _InkSignaturePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kNavyPrimary
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InkSignaturePainter oldDelegate) => true;
}
