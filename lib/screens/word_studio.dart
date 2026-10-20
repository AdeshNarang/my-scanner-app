import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/converter_engine.dart';

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kWhitePure = Colors.white;

class NativeWordDocumentStudio extends StatefulWidget {
  final String filePath;
  final String fileName;
  final String ext;
  final VoidCallback onSaved;

  const NativeWordDocumentStudio({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.ext,
    required this.onSaved,
  });

  @override
  State<NativeWordDocumentStudio> createState() => _NativeWordDocumentStudioState();
}

class _NativeWordDocumentStudioState extends State<NativeWordDocumentStudio> {
  final TextEditingController _docCtrl = TextEditingController();
  double _fontSize = 14.0;
  bool _isBold = false;
  bool _loading = true;
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _loadWordDoc();
  }

  Future<void> _loadWordDoc() async {
    final bytes = await File(widget.filePath).readAsBytes();
    final lines = await UniversalFormatConverterEngine.extractLinesFromDocx(bytes);
    setState(() {
      _docCtrl.text = lines.join('\n\n');
      _loading = false;
    });
  }

  Future<void> _saveWordDoc() async {
    final paragraphs = _docCtrl.text.split('\n');
    final docxBytes = UniversalFormatConverterEngine.buildDocxBytes(title: '', paragraphs: paragraphs);
    await File(widget.filePath).writeAsBytes(docxBytes);
    widget.onSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved Word (.docx) Document!'), backgroundColor: kBlueAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCBD5E1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D4ED8),
        title: Text(widget.fileName, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: kWhitePure)),
        actions: [
          IconButton(icon: Icon(_editMode ? Icons.visibility : Icons.edit, color: kWhitePure), onPressed: () => setState(() => _editMode = !_editMode)),
          IconButton(icon: const Icon(Icons.save_outlined, color: kWhitePure), onPressed: _saveWordDoc),
          IconButton(icon: const Icon(Icons.open_in_new, color: kWhitePure), onPressed: () => OpenFilex.open(widget.filePath)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: kWhitePure,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(
                    children: [
                      IconButton(icon: Icon(Icons.format_bold, color: _isBold ? kBlueAccent : kNavyPrimary), onPressed: () => setState(() => _isBold = !_isBold)),
                      const Text('Size:', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(value: _fontSize, min: 10, max: 28, activeColor: kBlueAccent, onChanged: (v) => setState(() => _fontSize = v)),
                      ),
                      Text('${_fontSize.round()} pt', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 3.5,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 680, minHeight: 880),
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(color: kWhitePure, borderRadius: BorderRadius.circular(4), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 14, offset: Offset(0, 4))]),
                          child: _editMode
                              ? TextField(controller: _docCtrl, maxLines: null, style: TextStyle(fontSize: _fontSize, fontWeight: _isBold ? FontWeight.bold : FontWeight.normal, height: 1.6, color: kNavyPrimary), decoration: const InputDecoration(border: InputBorder.none))
                              : SelectableText(_docCtrl.text, style: TextStyle(fontSize: _fontSize, fontWeight: _isBold ? FontWeight.bold : FontWeight.normal, height: 1.6, color: kNavyPrimary)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
