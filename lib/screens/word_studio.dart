import 'dart:typed_data';
import 'package:flutter/material.dart';

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kStudioLightBg = Color(0xFFF8FAFC);
const Color kWhitePure = Colors.white;
const Color kBorderSubtle = Color(0xFFE2E8F0);
const Color kSlateMuted = Color(0xFF64748B);

class NativeWordDocumentStudio extends StatefulWidget {
  final List<String> initialParagraphs;
  final String fileName;
  final Future<void> Function(List<String> updatedParagraphs, String fileName) onSaveDoc;

  const NativeWordDocumentStudio({
    super.key,
    required this.initialParagraphs,
    required this.fileName,
    required this.onSaveDoc,
  });

  @override
  State<NativeWordDocumentStudio> createState() => _NativeWordDocumentStudioState();
}

class _NativeWordDocumentStudioState extends State<NativeWordDocumentStudio> {
  late List<TextEditingController> _controllers;
  late TextEditingController _titleCtrl;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.fileName.replaceAll(RegExp(r'\.[^.]+?$'), ''));
    final paras = widget.initialParagraphs.isNotEmpty ? widget.initialParagraphs : ['Document Body Paragraph'];
    _controllers = paras.map((p) => TextEditingController(text: p)).toList();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addParagraph() {
    setState(() {
      _controllers.add(TextEditingController(text: 'New paragraph entry...'));
    });
  }

  void _removeParagraph(int index) {
    if (_controllers.length <= 1) return;
    setState(() {
      _controllers[index].dispose();
      _controllers.removeAt(index);
    });
  }

  Future<void> _handleSave() async {
    setState(() => _processing = true);
    try {
      final paras = _controllers.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
      await widget.onSaveDoc(paras, _titleCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved Word Document!'), backgroundColor: Color(0xFF15803D)),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kStudioLightBg,
      appBar: AppBar(
        backgroundColor: kWhitePure,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shape: const Border(bottom: BorderSide(color: kBorderSubtle)),
        title: SizedBox(
          width: 220,
          child: TextField(
            controller: _titleCtrl,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kNavyPrimary),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Add Paragraph',
            icon: const Icon(Icons.playlist_add, color: kBlueAccent),
            onPressed: _addParagraph,
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: kBlueAccent,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            onPressed: _processing ? null : _handleSave,
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          if (_processing) const LinearProgressIndicator(color: kBlueAccent),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _controllers.length,
              itemBuilder: (_, i) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kWhitePure,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorderSubtle),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w900, color: kSlateMuted, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _controllers[i],
                          maxLines: null,
                          style: const TextStyle(fontSize: 14, color: kNavyPrimary),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Type paragraph content...',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove Paragraph',
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () => _removeParagraph(i),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
