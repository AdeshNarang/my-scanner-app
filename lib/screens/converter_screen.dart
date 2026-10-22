import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/converter_engine.dart';

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kStudioLightBg = Color(0xFFF8FAFC);
const Color kWhitePure = Colors.white;
const Color kBorderSubtle = Color(0xFFE2E8F0);
const Color kSlateMuted = Color(0xFF64748B);

class FormatConverterScreen extends StatefulWidget {
  const FormatConverterScreen({super.key});

  @override
  State<FormatConverterScreen> createState() => _FormatConverterScreenState();
}

class _FormatConverterScreenState extends State<FormatConverterScreen> {
  String? _selectedFilePath;
  String _targetFormat = 'PDF';
  bool _converting = false;

  final List<String> _formats = ['PDF', 'DOCX', 'XLSX', 'TXT'];

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'doc', 'xlsx', 'xls', 'csv', 'tsv', 'txt', 'png', 'jpg', 'jpeg', 'webp'],
    );
    if (picked != null && picked.files.single.path != null) {
      setState(() => _selectedFilePath = picked.files.single.path);
    }
  }

  Future<void> _executeConversion() async {
    if (_selectedFilePath == null) return;
    setState(() => _converting = true);

    try {
      final srcFile = File(_selectedFilePath!);
      final bytes = await srcFile.readAsBytes();
      final baseName = p.basenameWithoutExtension(srcFile.path);
      
      final dir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory(p.join(dir.path, 'vault'));
      if (!await vaultDir.exists()) await vaultDir.create(recursive: true);

      String outPath = '';

      if (_targetFormat == 'PDF') {
        // Convert to PDF via text lines or builder
        final lines = await UniversalFormatConverterEngine.extractLinesFromDocx(bytes);
        final pdfBytes = UniversalFormatConverterEngine.buildDocxBytes(title: baseName, paragraphs: lines);
        outPath = p.join(vaultDir.path, '${baseName}_converted.pdf');
        await File(outPath).writeAsBytes(pdfBytes);
      } else if (_targetFormat == 'DOCX') {
        final lines = await UniversalFormatConverterEngine.extractLinesFromDocx(bytes);
        final docxBytes = UniversalFormatConverterEngine.buildDocxBytes(title: baseName, paragraphs: lines);
        outPath = p.join(vaultDir.path, '${baseName}_converted.docx');
        await File(outPath).writeAsBytes(docxBytes);
      } else if (_targetFormat == 'XLSX') {
        final rows = UniversalFormatConverterEngine.extractRowsFromExcelOrCsv(bytes, p.extension(srcFile.path));
        final xlsxBytes = UniversalFormatConverterEngine.buildExcelBytes(rows, sheetName: baseName);
        outPath = p.join(vaultDir.path, '${baseName}_converted.xlsx');
        await File(outPath).writeAsBytes(xlsxBytes);
      } else {
        // TXT
        final lines = await UniversalFormatConverterEngine.extractLinesFromDocx(bytes);
        outPath = p.join(vaultDir.path, '${baseName}_converted.txt');
        await File(outPath).writeAsString(lines.join('\n'));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully converted to $_targetFormat! Saved in Vault.'), backgroundColor: const Color(0xFF15803D)),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Conversion failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _converting = false);
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
        title: const Text('Format Converter Hub', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kNavyPrimary)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Source Document', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: kSlateMuted)),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pickFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kWhitePure,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kBorderSubtle),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.file_upload_outlined, color: kBlueAccent, size: 26),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _selectedFilePath != null ? p.basename(_selectedFilePath!) : 'Tap to select document (PDF, Word, Excel, Image)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: _selectedFilePath != null ? kNavyPrimary : kSlateMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Target Output Format', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: kSlateMuted)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: _formats.map((fmt) {
                final isSelected = _targetFormat == fmt;
                return ChoiceChip(
                  label: Text(fmt, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? kWhitePure : kNavyPrimary)),
                  selected: isSelected,
                  selectedColor: kBlueAccent,
                  backgroundColor: kWhitePure,
                  side: BorderSide(color: isSelected ? kBlueAccent : kBorderSubtle),
                  onSelected: (_) => setState(() => _targetFormat = fmt),
                );
              }).toList(),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kBlueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _selectedFilePath == null || _converting ? null : _executeConversion,
                icon: _converting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: kWhitePure, strokeWidth: 2)) : const Icon(Icons.transform),
                label: Text(_converting ? 'Converting...' : 'Convert & Save to Vault', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
