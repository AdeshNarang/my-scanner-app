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
