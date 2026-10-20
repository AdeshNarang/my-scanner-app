import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kBlueLight = Color(0xFFDBEAFE);
const Color kWhitePure = Colors.white;
const Color kSlateMuted = Color(0xFF64748B);

class LivePdfImageCompressionScreen extends StatefulWidget {
  final Uint8List originalBytes;
  final String fileName;
  final bool isPdf;
  final Future<void> Function(Uint8List compressedBytes, String outName) onSaveCompressed;

  const LivePdfImageCompressionScreen({
    super.key,
    required this.originalBytes,
    required this.fileName,
    required this.isPdf,
    required this.onSaveCompressed,
  });

  @override
  State<LivePdfImageCompressionScreen> createState() => _LivePdfImageCompressionScreenState();
}

class _LivePdfImageCompressionScreenState extends State<LivePdfImageCompressionScreen> {
  double _qualitySlider = 60;
  Uint8List? _previewCompressedBytes;
  bool _calculating = false;

  @override
  void initState() {
    super.initState();
    _recalculateCompressedSize();
  }

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _recalculateCompressedSize() async {
    setState(() => _calculating = true);
    final q = _qualitySlider.round();

    try {
      if (!widget.isPdf) {
        final comp = await FlutterImageCompress.compressWithList(widget.originalBytes, quality: q);
        if (mounted) setState(() => _previewCompressedBytes = comp);
      } else {
        final outPdf = pw.Document();
        final dpi = (72 + (q * 0.9)).round();
        await for (final page in Printing.raster(widget.originalBytes, dpi: dpi.toDouble())) {
          final png = await page.toPng();
          final jpg = await FlutterImageCompress.compressWithList(png, quality: q);
          outPdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(jpg), fit: pw.BoxFit.contain)),
            ),
          );
        }
        final saved = await outPdf.save();
        if (mounted) setState(() => _previewCompressedBytes = saved);
      }
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final origLen = widget.originalBytes.length;
    final compLen = _previewCompressedBytes?.length ?? origLen;
    final savedPercent = origLen > 0 ? ((1.0 - (compLen / origLen)) * 100).clamp(0.0, 99.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kNavyPrimary,
        title: const Text('PDF & Image Size Compressor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kWhitePure)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(widget.fileName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            const Text('ORIGINAL SIZE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kSlateMuted)),
                            const SizedBox(height: 6),
                            Text(_fmtSize(origLen), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kNavyPrimary)),
                          ],
                        ),
                        const Icon(Icons.arrow_forward_rounded, color: kBlueAccent, size: 28),
                        Column(
                          children: [
                            const Text('COMPRESSED SIZE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kBlueAccent)),
                            const SizedBox(height: 6),
                            _calculating
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                                : Text(_fmtSize(compLen), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF15803D))),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(20)),
                      child: Text('Space Saved: ${savedPercent.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w900, color: kBlueAccent, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Compression Quality Level:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('${_qualitySlider.round()}%', style: const TextStyle(fontWeight: FontWeight.w900, color: kBlueAccent, fontSize: 16)),
                      ],
                    ),
                    Slider(
                      value: _qualitySlider,
                      min: 15,
                      max: 95,
                      divisions: 16,
                      activeColor: kBlueAccent,
                      label: '${_qualitySlider.round()}%',
                      onChanged: (v) => setState(() => _qualitySlider = v),
                      onChangeEnd: (_) => _recalculateCompressedSize(),
                    ),
                    const Text('Lower percentage produces a smaller file size. Move the slider to preview exact output size.', style: TextStyle(fontSize: 12, color: kSlateMuted)),
                  ],
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kBlueAccent, padding: const EdgeInsets.symmetric(vertical: 15)),
                onPressed: _calculating || _previewCompressedBytes == null
                    ? null
                    : () async {
                        final outName = 'Compressed_${widget.fileName}';
                        await widget.onSaveCompressed(_previewCompressedBytes!, outName);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved $outName (${_fmtSize(compLen)}) to Vault!'), backgroundColor: const Color(0xFF15803D)));
                          Navigator.pop(context);
                        }
                      },
                icon: const Icon(Icons.save_alt),
                label: const Text('Save Compressed File to Vault', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
