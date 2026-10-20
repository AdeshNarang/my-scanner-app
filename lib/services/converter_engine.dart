import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:xml/xml.dart' as xml;

import '../models/document_models.dart';

class UniversalFormatConverterEngine {
  static TextRecognizer createRecognizer(OcrLanguageMode mode) {
    if (mode == OcrLanguageMode.hindiDevanagari) {
      return TextRecognizer(script: TextRecognitionScript.devanagari);
    }
    return TextRecognizer(script: TextRecognitionScript.latin);
  }

  static Future<List<String>> extractLinesFromDocx(Uint8List docxBytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(docxBytes);
      for (final file in archive) {
        if (file.name == 'word/document.xml' && file.isFile) {
          final content = utf8.decode(file.content as List<int>, allowMalformed: true);
          final document = xml.XmlDocument.parse(content);
          final paragraphs = document.findAllElements('w:p');
          final List<String> lines = [];
          for (final pNode in paragraphs) {
            final texts = pNode.findAllElements('w:t').map((e) => e.innerText).join();
            if (texts.trim().isNotEmpty) {
              lines.add(texts.trim());
            }
          }
          return lines.isEmpty ? [''] : lines;
        }
      }
    } catch (_) {}
    final raw = utf8.decode(docxBytes, allowMalformed: true);
    return raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
  }

  static Uint8List buildDocxBytes({
    required String title,
    required List<String> paragraphs,
    List<List<String>>? tableData,
  }) {
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

    const esc = HtmlEscape();
    final sb = StringBuffer();
    sb.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sb.write('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>');
    if (title.isNotEmpty) {
      sb.write('<w:p><w:r><w:rPr><w:b/><w:sz w:val="32"/></w:rPr><w:t>${esc.convert(title)}</w:t></w:r></w:p>');
    }
    for (final line in paragraphs) {
      sb.write('<w:p><w:r><w:t>${esc.convert(line)}</w:t></w:r></w:p>');
    }
    if (tableData != null && tableData.isNotEmpty) {
      sb.write('<w:tbl>');
      for (final row in tableData) {
        sb.write('<w:tr>');
        for (final cell in row) {
          sb.write('<w:tc><w:p><w:r><w:t>${esc.convert(cell)}</w:t></w:r></w:p></w:tc>');
        }
        sb.write('</w:tr>');
      }
      sb.write('</w:tbl>');
    }
    sb.write('</w:body></w:document>');
    final docStr = sb.toString();

    archive.addFile(ArchiveFile('[Content_Types].xml', contentTypesXml.length, utf8.encode(contentTypesXml)));
    archive.addFile(ArchiveFile('_rels/.rels', relsXml.length, utf8.encode(relsXml)));
    archive.addFile(ArchiveFile('word/document.xml', docStr.length, utf8.encode(docStr)));

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  static List<List<String>> extractRowsFromExcelOrCsv(Uint8List bytes, String ext) {
    final rawText = utf8.decode(bytes, allowMalformed: true);

    if (rawText.contains('<table') || rawText.contains('<TABLE')) {
      final List<List<String>> htmlRows = [];
      final rowMatches = RegExp(r'<tr[^>]*>(.*?)<\/tr>', caseSensitive: false, dotAll: true).allMatches(rawText);
      for (final rm in rowMatches) {
        final rowContent = rm.group(1) ?? '';
        final cellMatches = RegExp(r'<t[dh][^>]*>(.*?)<\/t[dh]>', caseSensitive: false, dotAll: true).allMatches(rowContent);
        final cells = cellMatches.map((cm) {
          return (cm.group(1) ?? '')
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .replaceAll('&nbsp;', ' ')
              .trim();
        }).toList();
        if (cells.isNotEmpty) htmlRows.add(cells);
      }
      if (htmlRows.isNotEmpty) return htmlRows;
    }

    if (rawText.contains('<?xml') && rawText.contains('ss:Workbook')) {
      try {
        final doc = xml.XmlDocument.parse(rawText);
        final List<List<String>> xmlRows = [];
        for (final row in doc.findAllElements('Row')) {
          final cells = row.findAllElements('Data').map((d) => d.innerText.trim()).toList();
          if (cells.isNotEmpty) xmlRows.add(cells);
        }
        if (xmlRows.isNotEmpty) return xmlRows;
      } catch (_) {}
    }

    if (ext.toUpperCase() == 'CSV' || (!rawText.startsWith('PK') && rawText.contains('\n'))) {
      final lines = rawText.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.length > 1) {
        final sep = lines.first.contains('\t') ? '\t' : ',';
        final parsed = lines.map((l) => l.split(sep).map((c) => c.replaceAll('"', '').trim()).toList()).toList();
        if (parsed.isNotEmpty && parsed.first.length > 1) return parsed;
      }
    }

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

    final List<String> harvested = [];
    final matches = RegExp(r'[\x20-\x7E]{3,}').allMatches(rawText);
    for (final m in matches) {
      final s = m.group(0)!.trim();
      if (s.length > 2 && !s.startsWith('CompObj') && !s.startsWith('Root Entry')) {
        harvested.add(s);
      }
    }
    if (harvested.isNotEmpty) {
      final List<List<String>> chunked = [];
      for (int i = 0; i < harvested.length; i += 4) {
        chunked.add(harvested.sublist(i, math.min(i + 4, harvested.length)));
      }
      return chunked;
    }

    return [['Item', 'Description', 'Quantity', 'Amount'], ['1', 'Sample Ledger Entry', '1', '0.00']];
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

  static Future<List<String>> extractOcrLinesFromPdf(Uint8List pdfBytes, OcrLanguageMode lang) async {
    final List<String> allLines = [];
    final tmpDir = await getTemporaryDirectory();
    int pageNum = 1;

    if (lang == OcrLanguageMode.punjabiGurmukhi) {
      await for (final page in Printing.raster(pdfBytes, dpi: 150)) {
        final png = await page.toPng();
        final tmpFile = File(p.join(tmpDir.path, 'ocr_conv_pan_$pageNum.png'));
        await tmpFile.writeAsBytes(png);
        final extracted = await FlutterTesseractOcr.extractText(tmpFile.path, language: 'pan');
        final lines = extracted.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
        allLines.addAll(lines);
        pageNum++;
      }
    } else {
      final recognizer = createRecognizer(lang);
      try {
        await for (final page in Printing.raster(pdfBytes, dpi: 150)) {
          final png = await page.toPng();
          final tmpFile = File(p.join(tmpDir.path, 'ocr_conv_$pageNum.png'));
          await tmpFile.writeAsBytes(png);
          final recognized = await recognizer.processImage(InputImage.fromFilePath(tmpFile.path));
          for (final block in recognized.blocks) {
            for (final line in block.lines) {
              allLines.add(line.text);
            }
          }
          pageNum++;
        }
      } finally {
        await recognizer.close();
      }
    }
    return allLines.isEmpty ? ['Document Page Content'] : allLines;
  }
}
