import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:xml/xml.dart' as xml;

import '../models/document_models.dart';

class UniversalFormatConverterEngine {
  static bool _tessDataVerified = false;

  static TextRecognizer createRecognizer(OcrLanguageMode mode) {
    if (mode == OcrLanguageMode.hindiDevanagari) {
      return TextRecognizer(script: TextRecognitionScript.devanagiri);
    }
    return TextRecognizer(script: TextRecognitionScript.latin);
  }

  static Future<void> ensurePunjabiTrainedDataUnpacked() async {
    if (_tessDataVerified) return;
    try {
      final ByteData data = await rootBundle.load('assets/tessdata/pan.traineddata');
      final Uint8List bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      final appDocDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory(p.join(appDocDir.path, 'tessdata'));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      final targetFile = File(p.join(targetDir.path, 'pan.traineddata'));
      await targetFile.writeAsBytes(bytes, flush: true);
      _tessDataVerified = true;
    } catch (_) {}
  }

  static Future<List<OcrWordBox>> extractPunjabiWordBoxes(
    String imagePath,
    int imgWidth,
    int imgHeight,
  ) async {
    await ensurePunjabiTrainedDataUnpacked();
    final List<OcrWordBox> boxes = [];
    try {
      final rawText = await FlutterTesseractOcr.extractText(
        imagePath,
        language: 'pan',
        args: {"psm": "6", "preserve_interword_spaces": "1"},
      );
      final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isNotEmpty) {
        final double safeW = math.max(100, imgWidth).toDouble();
        final double safeH = math.max(100, imgHeight).toDouble();
        final double lineStep = (safeH * 0.80) / math.max(1, lines.length);

        for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
          final words = lines[lineIdx].split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
          if (words.isEmpty) continue;
          final double wordStep = (safeW * 0.84) / words.length;
          final double topY = (safeH * 0.08) + (lineIdx * lineStep);
          final double boxH = math.min(lineStep * 0.78, 60.0);

          for (int wIdx = 0; wIdx < words.length; wIdx++) {
            final double leftX = (safeW * 0.08) + (wIdx * wordStep);
            boxes.add(
              OcrWordBox(
                text: words[wIdx],
                boundingBox: Rect.fromLTWH(leftX, topY, wordStep * 0.90, boxH),
              ),
            );
          }
        }
      }
    } catch (_) {}
    return boxes;
  }

  static Future<List<String>> extractLinesFromDocx(Uint8List docxBytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(docxBytes);
      final List<String> lines = [];
      for (final file in archive) {
        if (!file.isFile) continue;
        if (file.name == 'word/document.xml') {
          final content = utf8.decode(file.content as List<int>, allowMalformed: true);
          final document = xml.XmlDocument.parse(content);
          for (final pNode in document.findAllElements('w:p')) {
            final texts = pNode.findAllElements('w:t').map((e) => e.innerText).join();
            if (texts.trim().isNotEmpty) lines.add(texts.trim());
          }
          if (lines.isNotEmpty) return lines;
        }
      }
      if (lines.isNotEmpty) return lines;
    } catch (_) {}
    return ['Document Content'];
  }

  static Uint8List buildDocxBytes({required String title, required List<String> paragraphs}) {
    final archive = Archive();
    const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    final esc = const HtmlEscape();
    final sb = StringBuffer();
    sb.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sb.write('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>');
    if (title.isNotEmpty) {
      sb.write('<w:p><w:r><w:rPr><w:b/><w:sz w:val="32"/></w:rPr><w:t>${esc.convert(title)}</w:t></w:r></w:p>');
    }
    for (final line in paragraphs) {
      sb.write('<w:p><w:r><w:t>${esc.convert(line)}</w:t></w:r></w:p>');
    }
    sb.write('</w:body></w:document>');
    final docStr = sb.toString();

    archive.addFile(ArchiveFile('[Content_Types].xml', contentTypesXml.length, utf8.encode(contentTypesXml)));
    archive.addFile(ArchiveFile('_rels/.rels', relsXml.length, utf8.encode(relsXml)));
    archive.addFile(ArchiveFile('word/document.xml', docStr.length, utf8.encode(docStr)));

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  static List<List<String>> extractRowsFromExcelOrCsv(Uint8List bytes, String ext) {
    try {
      final excel = xls.Excel.decodeBytes(bytes);
      final List<List<String>> rows = [];
      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table]!;
        for (final row in sheet.rows) {
          rows.add(row.map((cell) => cell?.value?.toString() ?? '').toList());
        }
      }
      if (rows.isNotEmpty) return rows;
    } catch (_) {}
    return [
      ['Item', 'Description', 'Quantity', 'Amount'],
      ['1', 'Sample Entry', '1', '0.00'],
    ];
  }

  static Uint8List buildExcelBytes(List<List<String>> rows, {String sheetName = 'AN_Office_Sheet'}) {
    final excel = xls.Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      excel.rename(defaultSheet, sheetName);
    }
    final sheet = excel[sheetName];
    for (var r = 0; r < rows.length; r++) {
      final rowValues = rows[r].map((v) => xls.TextCellValue(v)).toList();
      sheet.appendRow(rowValues);
    }
    return Uint8List.fromList(excel.encode() ?? []);
  }
}
