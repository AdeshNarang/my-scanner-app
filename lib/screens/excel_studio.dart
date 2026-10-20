import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/converter_engine.dart';

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kBlueLight = Color(0xFFDBEAFE);
const Color kBlueIceBg = Color(0xFFF1F5F9);
const Color kWhitePure = Colors.white;
const Color kSlateMuted = Color(0xFF64748B);

class NativeExcelSpreadsheetStudio extends StatefulWidget {
  final String filePath;
  final String fileName;
  final String ext;
  final VoidCallback onSaved;

  const NativeExcelSpreadsheetStudio({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.ext,
    required this.onSaved,
  });

  @override
  State<NativeExcelSpreadsheetStudio> createState() => _NativeExcelSpreadsheetStudioState();
}

class _NativeExcelSpreadsheetStudioState extends State<NativeExcelSpreadsheetStudio> {
  List<List<String>> _grid = [];
  int _selectedRow = 0;
  int _selectedCol = 0;
  final TextEditingController _formulaCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGrid();
  }

  Future<void> _loadGrid() async {
    final bytes = await File(widget.filePath).readAsBytes();
    final extracted = UniversalFormatConverterEngine.extractRowsFromExcelOrCsv(bytes, widget.ext);

    int maxCols = 6;
    for (final r in extracted) {
      if (r.length > maxCols) maxCols = r.length;
    }
    final normalized = extracted.map((r) {
      final copy = List<String>.from(r);
      while (copy.length < maxCols) copy.add('');
      return copy;
    }).toList();
    while (normalized.length < 25) {
      normalized.add(List.filled(maxCols, ''));
    }

    setState(() {
      _grid = normalized;
      _formulaCtrl.text = _grid[0][0];
      _loading = false;
    });
  }

  String _colLetter(int index) {
    String res = '';
    int n = index;
    while (n >= 0) {
      res = String.fromCharCode(65 + (n % 26)) + res;
      n = (n ~/ 26) - 1;
    }
    return res;
  }

  Future<void> _saveSpreadsheet() async {
    final bytes = UniversalFormatConverterEngine.buildExcelBytes(_grid);
    await File(widget.filePath).writeAsBytes(bytes);
    widget.onSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved Excel Spreadsheet!'), backgroundColor: Color(0xFF15803D)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kWhitePure,
      appBar: AppBar(
        backgroundColor: const Color(0xFF15803D),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.fileName, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: kWhitePure)),
            const Text('Spreadsheet Grid (Pinch-to-Zoom Active)', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Save', icon: const Icon(Icons.save_outlined, color: kWhitePure), onPressed: _saveSpreadsheet),
          IconButton(tooltip: 'Open Externally', icon: const Icon(Icons.open_in_new, color: kWhitePure), onPressed: () => OpenFilex.open(widget.filePath)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: kBlueIceBg,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: kWhitePure, border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(6)),
                        child: Text('${_colLetter(_selectedCol)}${_selectedRow + 1}', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF15803D))),
                      ),
                      const SizedBox(width: 10),
                      const Text('fx', style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: kSlateMuted)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _formulaCtrl,
                          decoration: const InputDecoration(isDense: true, hintText: 'Enter cell value...', filled: true, fillColor: kWhitePure, border: OutlineInputBorder()),
                          onChanged: (val) => setState(() => _grid[_selectedRow][_selectedCol] = val),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    constrained: false,
                    minScale: 0.5,
                    maxScale: 3.5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(width: 46, height: 34, alignment: Alignment.center, color: const Color(0xFFE2E8F0), child: const Icon(Icons.grid_4x4, size: 14, color: kSlateMuted)),
                            ...List.generate(_grid.first.length, (c) {
                              return Container(
                                width: 125,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: c == _selectedCol ? const Color(0xFFDCFCE7) : const Color(0xFFE2E8F0), border: Border.all(color: Colors.grey.shade400, width: 0.5)),
                                child: Text(_colLetter(c), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kNavyPrimary)),
                              );
                            }),
                          ],
                        ),
                        ...List.generate(_grid.length, (r) {
                          return Row(
                            children: [
                              Container(
                                width: 46,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: r == _selectedRow ? const Color(0xFFDCFCE7) : const Color(0xFFE2E8F0), border: Border.all(color: Colors.grey.shade400, width: 0.5)),
                                child: Text('${r + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: kSlateMuted)),
                              ),
                              ...List.generate(_grid[r].length, (c) {
                                final isSel = r == _selectedRow && c == _selectedCol;
                                return GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedRow = r;
                                    _selectedCol = c;
                                    _formulaCtrl.text = _grid[r][c];
                                  }),
                                  child: Container(
                                    width: 125,
                                    height: 36,
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    alignment: Alignment.centerLeft,
                                    decoration: BoxDecoration(
                                      color: isSel ? const Color(0xFFF0FDF4) : kWhitePure,
                                      border: Border.all(color: isSel ? const Color(0xFF15803D) : Colors.grey.shade300, width: isSel ? 2.0 : 0.5),
                                    ),
                                    child: Text(_grid[r][c], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: r == 0 ? FontWeight.bold : FontWeight.normal)),
                                  ),
                                );
                              }),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
