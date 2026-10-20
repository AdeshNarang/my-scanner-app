import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/document_models.dart';
import '../services/converter_engine.dart';

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kNavySecondary = Color(0xFF1E293B);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kBlueLight = Color(0xFFDBEAFE);
const Color kWhitePure = Colors.white;

class InPlaceSelectableOcrScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final OcrLanguageMode initialLang;
  final ValueChanged<List<OcrWordBox>>? onOcrCompleted;

  const InPlaceSelectableOcrScreen({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    this.initialLang = OcrLanguageMode.english,
    this.onOcrCompleted,
  });

  @override
  State<InPlaceSelectableOcrScreen> createState() => _InPlaceSelectableOcrScreenState();
}

class _InPlaceSelectableOcrScreenState extends State<InPlaceSelectableOcrScreen> {
  late Uint8List _workingImageBytes;
  List<OcrWordBox> _wordBoxes = [];
  final Set<int> _selectedIndices = {};
  bool _runningOcr = true;
  late OcrLanguageMode _lang;
  String _searchFilter = '';

  @override
  void initState() {
    super.initState();
    _workingImageBytes = widget.imageBytes;
    _lang = widget.initialLang;
    _performInPlaceOcr();
  }

  Future<void> _performInPlaceOcr() async {
    setState(() {
      _runningOcr = true;
      _wordBoxes.clear();
      _selectedIndices.clear();
    });

    final tmpDir = await getTemporaryDirectory();
    final tmpFile = File(p.join(tmpDir.path, 'inplace_ocr_tmp.png'));
    await tmpFile.writeAsBytes(_workingImageBytes);

    final recognizer = UniversalFormatConverterEngine.createRecognizer(_lang);
    try {
      final recognized = await recognizer.processImage(InputImage.fromFilePath(tmpFile.path));
      final List<OcrWordBox> boxes = [];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            boxes.add(OcrWordBox(text: element.text, boundingBox: element.boundingBox));
          }
        }
      }
      if (mounted) {
        setState(() {
          _wordBoxes = boxes;
          _runningOcr = false;
        });
        widget.onOcrCompleted?.call(boxes);
      }
    } catch (_) {
      if (mounted) setState(() => _runningOcr = false);
    } finally {
      await recognizer.close();
    }
  }

  Future<void> _editWordInPhoto(OcrWordBox wb) async {
    final editCtrl = TextEditingController(text: wb.text);
    final confirmedNewText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seamless In-Photo Text Edit', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Original Text: "${wb.text}"', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(controller: editCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'New In-Photo Text', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBlueAccent),
            onPressed: () => Navigator.pop(ctx, editCtrl.text.trim()),
            child: const Text('Inpaint & Replace'),
          ),
        ],
      ),
    );

    if (confirmedNewText != null && confirmedNewText.isNotEmpty) {
      final decoded = img.decodeImage(_workingImageBytes);
      if (decoded == null) return;

      final r = wb.boundingBox;
      final sampleX = (r.left - 4).clamp(0, decoded.width - 1).toInt();
      final sampleY = (r.top - 4).clamp(0, decoded.height - 1).toInt();
      final bgPixel = decoded.getPixel(sampleX, sampleY);

      // Inpaint/erase original text with paper texture
      img.fillRect(
        decoded,
        x1: r.left.toInt() - 2,
        y1: r.top.toInt() - 2,
        x2: r.right.toInt() + 2,
        y2: r.bottom.toInt() + 2,
        color: bgPixel,
      );

      final updatedBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 95));
      setState(() => _workingImageBytes = updatedBytes);
      await _performInPlaceOcr();
    }
  }

  String get _selectedTextString {
    final sorted = _selectedIndices.toList()..sort();
    return sorted.map((i) => _wordBoxes[i].text).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavyPrimary,
      appBar: AppBar(
        backgroundColor: kNavyPrimary,
        title: TextField(
          style: const TextStyle(color: kWhitePure, fontSize: 14.5),
          decoration: const InputDecoration(
            hintText: 'Search or tap word to edit...',
            hintStyle: TextStyle(color: Colors.white60, fontSize: 13),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, color: kBlueLight, size: 18),
          ),
          onChanged: (v) {
            setState(() {
              _searchFilter = v.trim().toLowerCase();
              _selectedIndices.clear();
              if (_searchFilter.isNotEmpty) {
                for (int i = 0; i < _wordBoxes.length; i++) {
                  if (_wordBoxes[i].text.toLowerCase().contains(_searchFilter)) {
                    _selectedIndices.add(i);
                  }
                }
              }
            });
          },
        ),
        actions: [
          PopupMenuButton<OcrLanguageMode>(
            tooltip: 'Switch OCR Language',
            icon: const Icon(Icons.translate, color: kBlueLight),
            onSelected: (m) {
              setState(() => _lang = m);
              _performInPlaceOcr();
            },
            itemBuilder: (_) => OcrLanguageMode.values.map((m) => PopupMenuItem(value: m, child: Text(m.label))).toList(),
          ),
          IconButton(
            tooltip: 'Save In-Photo Edits',
            icon: const Icon(Icons.check, color: kWhitePure),
            onPressed: () => Navigator.pop(context, _workingImageBytes),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_runningOcr) const LinearProgressIndicator(color: kBlueAccent),
          Expanded(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 6.0,
              panEnabled: true,
              scaleEnabled: true,
              child: Center(
                child: AspectRatio(
                  aspectRatio: widget.imageWidth / math.max(1, widget.imageHeight),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scaleX = constraints.maxWidth / widget.imageWidth;
                      final scaleY = constraints.maxHeight / widget.imageHeight;

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(_workingImageBytes, fit: BoxFit.fill),
                          ...List.generate(_wordBoxes.length, (i) {
                            final wb = _wordBoxes[i];
                            final r = wb.boundingBox;
                            final isSelected = _selectedIndices.contains(i);
                            return Positioned(
                              left: r.left * scaleX,
                              top: r.top * scaleY,
                              width: math.max(8, r.width * scaleX),
                              height: math.max(8, r.height * scaleY),
                              child: GestureDetector(
                                onTap: () => _editWordInPhoto(wb),
                                onLongPress: () => setState(() {
                                  if (isSelected) {
                                    _selectedIndices.remove(i);
                                  } else {
                                    _selectedIndices.add(i);
                                  }
                                }),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected ? kBlueAccent.withOpacity(0.42) : kWhitePure.withOpacity(0.14),
                                    border: Border.all(color: isSelected ? kWhitePure : kBlueAccent.withOpacity(0.55), width: isSelected ? 1.6 : 0.7),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            color: kNavySecondary,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedIndices.isEmpty ? 'Tap any word to edit in photo. Long press to copy.' : 'Selected: $_selectedTextString',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kWhitePure, fontSize: 12.5),
                  ),
                ),
                if (_selectedIndices.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kBlueAccent),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _selectedTextString));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied text!')));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
