import 'dart:typed_data';
import 'package:flutter/material.dart';

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kBlueLight = Color(0xFFDBEAFE);
const Color kStudioLightBg = Color(0xFFF8FAFC);
const Color kWhitePure = Colors.white;
const Color kBorderSubtle = Color(0xFFE2E8F0);
const Color kSlateMuted = Color(0xFF64748B);

class NativeExcelSpreadsheetStudio extends StatefulWidget {
  final List<List<String>> initialRows;
  final String fileName;
  final Future<void> Function(List<List<String>> updatedRows, String fileName) onSaveSheet;

  const NativeExcelSpreadsheetStudio({
    super.key,
    required this.initialRows,
    required this.fileName,
    required this.onSaveSheet,
  });

  @override
  State<NativeExcelSpreadsheetStudio> createState() => _NativeExcelSpreadsheetStudioState();
}

class _NativeExcelSpreadsheetStudioState extends State<NativeExcelSpreadsheetStudio> {
  late List<List<String>> _rows;
  late TextEditingController _titleCtrl;
  int _selectedRow = 0;
  int _selectedCol = 0;
  late TextEditingController _cellEditorCtrl;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _rows = widget.initialRows.isNotEmpty
        ? widget.initialRows.map((r) => List<String>.from(r)).toList()
        : [
            ['Item', 'Description', 'Quantity', 'Amount'],
            ['1', 'Ledger Entry Alpha', '1', '1000.00']
          ];
    _titleCtrl = TextEditingController(text: widget.fileName.replaceAll(RegExp(r'\.[^.]+?$'), ''));
    _cellEditorCtrl = TextEditingController(text: _getCellVal(_selectedRow, _selectedCol));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _cellEditorCtrl.dispose();
    super.dispose();
  }

  String _getCellVal(int r, int c) {
    if (r < _rows.length && c < _rows[r].length) {
      return _rows[r][c];
    }
    return '';
  }

  void _updateCellVal(int r, int c, String val) {
    setState(() {
      while (_rows.length <= r) {
        _rows.add(List.filled(_rows.isNotEmpty ? _rows[0].length : 4, ''));
      }
      while (_rows[r].length <= c) {
        _rows[r].add('');
      }
      _rows[r][c] = val;
    });
  }

  String _getColLetter(int index) {
    String letter = '';
    int temp = index + 1;
    while (temp > 0) {
      int remainder = (temp - 1) % 26;
      letter = String.fromCharCode(65 + remainder) + letter;
      temp = (temp - 1) ~/ 26;
    }
    return letter;
  }

  void _addRowBelow() {
    setState(() {
      final colCount = _rows.isNotEmpty ? _rows[0].length : 4;
      _rows.insert(_selectedRow + 1, List.filled(colCount, ''));
      _selectedRow++;
      _cellEditorCtrl.text = '';
    });
  }

  void _addColumnRight() {
    setState(() {
      for (int i = 0; i < _rows.length; i++) {
        _rows[i].add('');
      }
      _selectedCol++;
      _cellEditorCtrl.text = '';
    });
  }

  void _deleteCurrentRow() {
    if (_rows.length <= 1) return;
    setState(() {
      _rows.removeAt(_selectedRow);
      if (_selectedRow >= _rows.length) _selectedRow = _rows.length - 1;
      _cellEditorCtrl.text = _getCellVal(_selectedRow, _selectedCol);
    });
  }

  Future<void> _handleSave() async {
    setState(() => _processing = true);
    try {
      await widget.onSaveSheet(_rows, _titleCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved Spreadsheet Changes!'), backgroundColor: Color(0xFF15803D)),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    int maxCols = 0;
    for (final r in _rows) {
      if (r.length > maxCols) maxCols = r.length;
    }
    if (maxCols < 5) maxCols = 5;

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
            tooltip: 'Add Row Below',
            icon: const Icon(Icons.playlist_add, color: kBlueAccent),
            onPressed: _addRowBelow,
          ),
          IconButton(
            tooltip: 'Add Column Right',
            icon: const Icon(Icons.view_column, color: kBlueAccent),
            onPressed: _addColumnRight,
          ),
          IconButton(
            tooltip: 'Delete Row',
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
            onPressed: _deleteCurrentRow,
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
          Container(
            color: kWhitePure,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kBorderSubtle)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: kBlueLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_getColLetter(_selectedCol)}${_selectedRow + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: kBlueAccent),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('fx', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kSlateMuted)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _cellEditorCtrl,
                    style: const TextStyle(fontSize: 14, color: kNavyPrimary, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      hintText: 'Enter cell value or formula...',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (v) => _updateCellVal(_selectedRow, _selectedCol, v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 3.5,
              panEnabled: true,
              scaleEnabled: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(kNavyPrimary),
                    border: TableBorder.all(color: kBorderSubtle, width: 1),
                    columns: List.generate(maxCols, (cIdx) {
                      return DataColumn(
                        label: Text(
                          _getColLetter(cIdx),
                          style: const TextStyle(color: kWhitePure, fontWeight: FontWeight.w900),
                        ),
                      );
                    }),
                    rows: List.generate(_rows.length, (rIdx) {
                      return DataRow(
                        cells: List.generate(maxCols, (cIdx) {
                          final val = _getCellVal(rIdx, cIdx);
                          final isSelected = _selectedRow == rIdx && _selectedCol == cIdx;
                          return DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              color: isSelected ? kBlueLight.withOpacity(0.6) : Colors.transparent,
                              child: Text(
                                val,
                                style: TextStyle(
                                  color: rIdx == 0 ? kNavyPrimary : Colors.black87,
                                  fontWeight: rIdx == 0 ? FontWeight.w900 : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            onTap: () {
                              setState(() {
                                _selectedRow = rIdx;
                                _selectedCol = cIdx;
                                _cellEditorCtrl.text = val;
                              });
                            },
                          );
                        }),
                      );
                    }),
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
