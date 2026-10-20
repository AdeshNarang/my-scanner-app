import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/document_models.dart';
import '../services/converter_engine.dart';
import 'ocr_editor.dart';
import 'pdf_studio.dart';

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kNavySecondary = Color(0xFF1E293B);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kBlueLight = Color(0xFFDBEAFE);
const Color kBlueIceBg = Color(0xFFF1F5F9);
const Color kWhitePure = Colors.white;
const Color kSlateMuted = Color(0xFF64748B);

class TruePdfReaderScreen extends StatefulWidget {
  final String filePath;
  final String fileName;
  final int defaultQuality;
  final OcrLanguageMode ocrLang;
  final VoidCallback onFileUpdated;

  const TruePdfReaderScreen({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.defaultQuality,
    required this.ocrLang,
    required this.onFileUpdated,
  });

  @override
  State<TruePdfReaderScreen> createState() => _TruePdfReaderScreenState();
}

class _TruePdfReaderScreenState extends State<TruePdfReaderScreen> {
  final List<EditableDocumentPage> _pages = [];
  final ScrollController _scrollController = ScrollController();
  bool _loadingPages = true;
  bool _isEncrypted = false;
  String? _errorMessage;

  bool _showSearchBar = false;
  final TextEditingController _searchCtrl = TextEditingController();
  List<GlobalSearchMatch> _searchMatches = [];
  GlobalSearchMatch? _highlightedMatch;

  @override
  void initState() {
    super.initState();
    _rasterizePdfForReader();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isEncryptedPdf(Uint8List bytes) {
    final sampleLen = math.min(bytes.length, 4096);
    final headerAscii = String.fromCharCodes(bytes.sublist(0, sampleLen));
    final trailerStart = math.max(0, bytes.length - 4096);
    final trailerAscii = String.fromCharCodes(bytes.sublist(trailerStart));
    return headerAscii.contains('/Encrypt') || trailerAscii.contains('/Encrypt');
  }

  Future<void> _rasterizePdfForReader() async {
    setState(() {
      _loadingPages = true;
      _isEncrypted = false;
      _errorMessage = null;
      _pages.clear();
    });

    try {
      final bytes = await File(widget.filePath).readAsBytes();

      if (_isEncryptedPdf(bytes)) {
        if (mounted) {
          setState(() {
            _loadingPages = false;
            _isEncrypted = true;
          });
        }
        return;
      }

      final List<EditableDocumentPage> loadedPages = [];
      await for (final rasterPage in Printing.raster(bytes, dpi: 150)) {
        final png = await rasterPage.toPng();
        loadedPages.add(
          EditableDocumentPage(
            originalBytes: png,
            displayBytes: png,
            imageWidth: rasterPage.width,
            imageHeight: rasterPage.height,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _pages.addAll(loadedPages);
        _loadingPages = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingPages = false;
          final errStr = e.toString().toLowerCase();
          if (errStr.contains('password') || errStr.contains('security') || errStr.contains('encrypt')) {
            _isEncrypted = true;
          } else {
            _errorMessage = 'Error loading document: $e';
          }
        });
      }
    }
  }

  void _jumpToSearchMatch(GlobalSearchMatch match) {
    setState(() => _highlightedMatch = match);
    if (_scrollController.hasClients) {
      final estimatedOffset = match.pageIndex * 480.0;
      _scrollController.animateTo(
        estimatedOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _runGlobalDocumentSearch(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) {
      setState(() {
        _searchMatches.clear();
        _highlightedMatch = null;
      });
      return;
    }

    final recognizer = UniversalFormatConverterEngine.createRecognizer(widget.ocrLang);
    final tmpDir = await getTemporaryDirectory();
    final List<GlobalSearchMatch> found = [];

    try {
      for (int pIdx = 0; pIdx < _pages.length; pIdx++) {
        final page = _pages[pIdx];
        if (page.ocrWords.isEmpty) {
          final tmpFile = File(p.join(tmpDir.path, 'reader_ocr_$pIdx.png'));
          await tmpFile.writeAsBytes(page.displayBytes);
          final recognized = await recognizer.processImage(InputImage.fromFilePath(tmpFile.path));
          for (final block in recognized.blocks) {
            for (final line in block.lines) {
              for (final el in line.elements) {
                page.ocrWords.add(OcrWordBox(text: el.text, boundingBox: el.boundingBox));
              }
            }
          }
        }

        for (final wb in page.ocrWords) {
          if (wb.text.toLowerCase().contains(cleanQuery)) {
            found.add(GlobalSearchMatch(pageIndex: pIdx, matchedLine: wb.text, wordRect: wb.boundingBox));
          }
        }
      }
    } finally {
      await recognizer.close();
    }

    if (mounted) {
      setState(() {
        _searchMatches = found;
        if (found.isNotEmpty) {
          _jumpToSearchMatch(found.first);
        }
      });
    }
  }

  Future<void> _switchToFullEditorMode() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AcrobatDocumentStudioScreen(
          initialPages: _pages,
          initialTitle: widget.fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
          defaultQuality: widget.defaultQuality,
          ocrLang: widget.ocrLang,
          onSaveDocument: (updatedBytes, finalName) async {
            await File(widget.filePath).writeAsBytes(updatedBytes);
            widget.onFileUpdated();
          },
        ),
      ),
    );
    await _rasterizePdfForReader();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF334155),
      appBar: AppBar(
        backgroundColor: kNavyPrimary,
        title: _showSearchBar
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: kWhitePure, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Search word across all pages...',
                  hintStyle: TextStyle(color: Colors.white60),
                  border: InputBorder.none,
                ),
                onSubmitted: _runGlobalDocumentSearch,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.fileName, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: kWhitePure), maxLines: 1),
                  Text(
                    _isEncrypted ? 'Password Protected' : '${_pages.length} Pages • Pinch to Zoom',
                    style: const TextStyle(fontSize: 11, color: kBlueLight),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_showSearchBar ? Icons.close : Icons.search, color: kWhitePure),
            onPressed: () => setState(() => _showSearchBar = !_showSearchBar),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: kWhitePure),
            onPressed: () => Share.shareXFiles([XFile(widget.filePath)]),
          ),
          if (!_isEncrypted)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kBlueAccent),
                onPressed: _pages.isEmpty ? null : _switchToFullEditorMode,
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('Edit PDF', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
      body: _loadingPages
          ? const Center(child: CircularProgressIndicator(color: kWhitePure))
          : _isEncrypted
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Card(
                      color: kNavySecondary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.lock_rounded, size: 48, color: Colors.amber),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Password Protected Document',
                              style: TextStyle(
                                color: kWhitePure,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'This PDF is encrypted. Tap below to securely unlock and view it using your phone’s system viewer.',
                              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: kBlueAccent,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => OpenFilex.open(widget.filePath),
                                icon: const Icon(Icons.lock_open_rounded, size: 20),
                                label: const Text(
                                  'Unlock in Secure PDF Viewer',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28.0),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: kWhitePure, fontSize: 14),
                        ),
                      ),
                    )
                  : InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 6.0,
                      panEnabled: true,
                      scaleEnabled: true,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        itemCount: _pages.length,
                        itemBuilder: (_, i) {
                          final page = _pages[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: kWhitePure,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  color: kBlueIceBg,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Page ${i + 1} of ${_pages.length}',
                                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kNavyPrimary),
                                      ),
                                      TextButton.icon(
                                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => InPlaceSelectableOcrScreen(
                                                imageBytes: page.displayBytes,
                                                imageWidth: page.imageWidth,
                                                imageHeight: page.imageHeight,
                                                initialLang: widget.ocrLang,
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.text_fields, size: 14, color: kBlueAccent),
                                        label: const Text('Select Text', style: TextStyle(fontSize: 11.5, color: kBlueAccent)),
                                      ),
                                    ],
                                  ),
                                ),
                                AspectRatio(
                                  aspectRatio: page.imageWidth / math.max(1, page.imageHeight),
                                  child: Image.memory(page.displayBytes, fit: BoxFit.fill),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
