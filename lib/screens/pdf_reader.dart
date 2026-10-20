import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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
  String? _errorMessage;
  String? _currentPassword;

  bool _showSearchBar = false;
  final TextEditingController _searchCtrl = TextEditingController();
  List<GlobalSearchMatch> _searchMatches = [];
  GlobalSearchMatch? _highlightedMatch;

  @override
  void initState() {
    super.initState();
    _rasterizePdfForReader();
  }

  bool _isEncryptedPdf(Uint8List bytes) {
    final sampleLen = math.min(bytes.length, 4096);
    final headerAscii = String.fromCharCodes(bytes.sublist(0, sampleLen));
    final trailerStart = math.max(0, bytes.length - 4096);
    final trailerAscii = String.fromCharCodes(bytes.sublist(trailerStart));
    return headerAscii.contains('/Encrypt') || trailerAscii.contains('/Encrypt');
  }

  Future<String?> _promptPasswordDialog({bool isRetry = false}) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.lock_outline, color: kBlueAccent),
            const SizedBox(width: 10),
            Text(isRetry ? 'Incorrect Password' : 'Password Protected PDF'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isRetry
                  ? 'The password entered was incorrect. Please try again.'
                  : 'This document is encrypted. Please enter the password to unlock it.',
              style: const TextStyle(fontSize: 13, color: kSlateMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Document Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBlueAccent),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Unlock Document'),
          ),
        ],
      ),
    );
  }

  Future<void> _rasterizePdfForReader({String? password}) async {
    setState(() {
      _loadingPages = true;
      _errorMessage = null;
      _pages.clear();
    });

    try {
      final bytes = await File(widget.filePath).readAsBytes();

      if (password == null && _isEncryptedPdf(bytes)) {
        final entered = await _promptPasswordDialog();
        if (entered == null || entered.isEmpty) {
          if (mounted) {
            setState(() {
              _loadingPages = false;
              _errorMessage = 'Password required to open this protected document.';
            });
          }
          return;
        }
        password = entered;
      }

      final List<EditableDocumentPage> loadedPages = [];
      try {
        await for (final rasterPage in Printing.raster(bytes, dpi: 150, password: password)) {
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
      } catch (_) {
        final retryPassword = await _promptPasswordDialog(isRetry: true);
        if (retryPassword != null && retryPassword.isNotEmpty) {
          await _rasterizePdfForReader(password: retryPassword);
          return;
        } else {
          if (mounted) {
            setState(() {
              _loadingPages = false;
              _errorMessage = 'Failed to decrypt document. Incorrect password.';
            });
          }
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _currentPassword = password;
        _pages.addAll(loadedPages);
        _loadingPages = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingPages = false;
          _errorMessage = 'Error loading document: $e';
        });
      }
    }
  }

  void _scrollToMatch(GlobalSearchMatch match) {
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
          _scrollToMatch(found.first);
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
    await _rasterizePdfForReader(password: _currentPassword);
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
                  Text('${_pages.length} Pages • Pinch to Zoom', style: const TextStyle(fontSize: 11, color: kBlueLight)),
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
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_person_outlined, size: 54, color: Colors.amberAccent),
                        const SizedBox(height: 14),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: kWhitePure, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: kBlueAccent),
                          onPressed: () => _rasterizePdfForReader(),
                          icon: const Icon(Icons.key_rounded, size: 18),
                          label: const Text('Unlock with Password'),
                        ),
                      ],
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
