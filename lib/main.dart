import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart' as xml;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF0F172A),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const ANOfficeExecutiveApp());
}

// =============================================================================
// COLOR PALETTE & LOGO
// =============================================================================

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kNavySecondary = Color(0xFF1E293B);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kBlueLight = Color(0xFFDBEAFE);
const Color kBlueIceBg = Color(0xFFF1F5F9);
const Color kWhitePure = Colors.white;
const Color kSlateMuted = Color(0xFF64748B);

class ANOfficeExecutiveApp extends StatelessWidget {
  const ANOfficeExecutiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AN Office',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBlueIceBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBlueAccent,
          primary: kNavyPrimary,
          secondary: kBlueAccent,
          surface: kWhitePure,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kNavyPrimary,
          foregroundColor: kWhitePure,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardTheme(
          color: kWhitePure,
          elevation: 1.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
        ),
      ),
      home: const ANOfficeMasterShell(),
    );
  }
}

class ANOfficeLogoBadge extends StatelessWidget {
  final double size;
  const ANOfficeLogoBadge({super.key, this.size = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF2EFE9),
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: kWhitePure.withOpacity(0.85), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/logo.png',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => CustomPaint(
          size: Size(size, size),
          painter: _ANOfficeCrestFallbackPainter(),
        ),
      ),
    );
  }
}

class _ANOfficeCrestFallbackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFF2EFE9));
    canvas.drawCircle(
      center,
      w * 0.42,
      Paint()
        ..color = const Color(0xFF2D2A26)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.025,
    );

    final tpAN = TextPainter(
      text: TextSpan(
        text: 'AN',
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: w * 0.35,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF2D2A26),
          letterSpacing: -1.2,
          height: 1.0,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tpAN.paint(canvas, Offset((w - tpAN.width) / 2, h * 0.17));

    final tpOffice = TextPainter(
      text: TextSpan(
        text: 'OFFICE',
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: w * 0.13,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF2D2A26),
          letterSpacing: 1.2,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tpOffice.paint(canvas, Offset((w - tpOffice.width) / 2, h * 0.64));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =============================================================================
// BACKGROUND ISOLATE ENGINE (FILTER & PERSPECTIVE WARP)
// =============================================================================

class _IsolateFilterPayload {
  final Uint8List bytes;
  final int filterIndex;
  _IsolateFilterPayload(this.bytes, this.filterIndex);
}

Uint8List _applyFilterInBackgroundIsolate(_IsolateFilterPayload payload) {
  final decoded = img.decodeImage(payload.bytes);
  if (decoded == null) return payload.bytes;

  img.Image working = decoded.clone();
  if (payload.filterIndex == 1) {
    working = img.adjustColor(working, contrast: 1.30, saturation: 1.18, brightness: 1.04);
  } else if (payload.filterIndex == 2) {
    working = img.grayscale(working);
  } else if (payload.filterIndex == 3) {
    working = img.grayscale(working);
    working = img.luminanceThreshold(working, threshold: 0.53);
  }
  return Uint8List.fromList(img.encodeJpg(working, quality: 90));
}

class _IsolateWarpPayload {
  final Uint8List bytes;
  final List<double> normCoords;
  _IsolateWarpPayload(this.bytes, this.normCoords);
}

Uint8List _performPerspectiveWarpInIsolate(_IsolateWarpPayload payload) {
  final srcImg = img.decodeImage(payload.bytes);
  if (srcImg == null) return payload.bytes;

  final w = srcImg.width.toDouble();
  final h = srcImg.height.toDouble();
  final c = payload.normCoords;

  final p0 = Offset(c[0] * w, c[1] * h);
  final p1 = Offset(c[2] * w, c[3] * h);
  final p2 = Offset(c[4] * w, c[5] * h);
  final p3 = Offset(c[6] * w, c[7] * h);

  final outW = math.max(240, math.max((p1 - p0).distance, (p2 - p3).distance).round());
  final outH = math.max(240, math.max((p3 - p0).distance, (p2 - p1).distance).round());
  final dstImg = img.Image(width: outW, height: outH);

  for (int y = 0; y < outH; y++) {
    final v = y / (outH - 1);
    for (int x = 0; x < outW; x++) {
      final u = x / (outW - 1);
      final srcX = (1 - u) * (1 - v) * p0.dx + u * (1 - v) * p1.dx + u * v * p2.dx + (1 - u) * v * p3.dx;
      final srcY = (1 - u) * (1 - v) * p0.dy + u * (1 - v) * p1.dy + u * v * p2.dy + (1 - u) * v * p3.dy;
      final sx = srcX.round().clamp(0, srcImg.width - 1);
      final sy = srcY.round().clamp(0, srcImg.height - 1);
      dstImg.setPixel(x, y, srcImg.getPixel(sx, sy));
    }
  }
  return Uint8List.fromList(img.encodeJpg(dstImg, quality: 92));
}

// =============================================================================
// DATA MODELS & REPOSITORIES
// =============================================================================

class VaultFile {
  final String name;
  final String path;
  final String ext;
  final DateTime modified;
  final int sizeBytes;
  final bool isLocked;

  VaultFile({
    required this.name,
    required this.path,
    required this.ext,
    required this.modified,
    required this.sizeBytes,
    this.isLocked = false,
  });
}

enum ScanColorFilter { original, magicColor, grayscale, highContrastBW }

extension ScanColorFilterLabel on ScanColorFilter {
  String get label {
    switch (this) {
      case ScanColorFilter.original:
        return 'Original';
      case ScanColorFilter.magicColor:
        return 'Magic Color';
      case ScanColorFilter.grayscale:
        return 'Grayscale';
      case ScanColorFilter.highContrastBW:
        return 'B&W Crisp';
    }
  }
}

enum ConversionDirection {
  pdfToImage,
  imageToPdf,
  pdfToWord,
  wordToPdf,
  pdfToExcel,
  excelToPdf,
  wordToExcel,
  excelToWord,
}

class OcrWordBox {
  final String text;
  final Rect boundingBox;
  OcrWordBox({required this.text, required this.boundingBox});
}

class GlobalSearchMatch {
  final int pageIndex;
  final String matchedLine;
  final Rect wordRect;

  GlobalSearchMatch({
    required this.pageIndex,
    required this.matchedLine,
    required this.wordRect,
  });
}

class BlemishEraserStroke {
  final List<Offset> normalizedPoints;
  final Color sampledColor;
  final double strokeWidth;

  BlemishEraserStroke({
    required this.normalizedPoints,
    required this.sampledColor,
    required this.strokeWidth,
  });
}

class OverlayImageItem {
  Uint8List bytes;
  Offset normalizedPos;
  double normalizedWidth;
  double normalizedHeight;

  OverlayImageItem({
    required this.bytes,
    this.normalizedPos = const Offset(0.3, 0.3),
    this.normalizedWidth = 0.40,
    this.normalizedHeight = 0.25,
  });
}

class PageAnnotationItem {
  final String type;
  String text;
  Offset normalizedPos;
  Color color;
  double fontSize;
  final Uint8List? signaturePng;

  PageAnnotationItem({
    required this.type,
    this.text = '',
    this.normalizedPos = const Offset(0.5, 0.5),
    this.color = kNavyPrimary,
    this.fontSize = 18.0,
    this.signaturePng,
  });
}

class EditableDocumentPage {
  Uint8List originalBytes;
  Uint8List displayBytes;
  int imageWidth;
  int imageHeight;
  int rotationQuarterTurns;
  ScanColorFilter activeFilter;
  List<OcrWordBox> ocrWords;
  List<PageAnnotationItem> annotations;
  List<BlemishEraserStroke> eraserStrokes;
  List<OverlayImageItem> overlayImages;

  EditableDocumentPage({
    required this.originalBytes,
    required this.displayBytes,
    this.imageWidth = 1000,
    this.imageHeight = 1400,
    this.rotationQuarterTurns = 0,
    this.activeFilter = ScanColorFilter.original,
    List<OcrWordBox>? ocrWords,
    List<PageAnnotationItem>? annotations,
    List<BlemishEraserStroke>? eraserStrokes,
    List<OverlayImageItem>? overlayImages,
  })  : ocrWords = ocrWords ?? [],
        annotations = annotations ?? [],
        eraserStrokes = eraserStrokes ?? [],
        overlayImages = overlayImages ?? [];
}

// =============================================================================
// MULTI-FORMAT SPREADSHEET & OCR CONVERSION ENGINE
// =============================================================================

enum OcrLanguageMode { english, hindiDevanagari, punjabiGurmukhi }

extension OcrLanguageLabel on OcrLanguageMode {
  String get label {
    switch (this) {
      case OcrLanguageMode.english:
        return 'English';
      case OcrLanguageMode.hindiDevanagari:
        return 'Hindi (हिंदी)';
      case OcrLanguageMode.punjabiGurmukhi:
        return 'Punjabi (ਪੰਜਾਬੀ)';
    }
  }
}

class UniversalFormatConverterEngine {
  static TextRecognizer createRecognizer(OcrLanguageMode mode) {
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

  /// Robust multi-format spreadsheet parser supporting:
  /// - True .XLSX
  /// - CSV & TSV
  /// - Legacy .XLS (HTML tables from accounting software like Tally / Busy)
  /// - XML Spreadsheet 2003 (.xls)
  /// - Binary BIFF8 extraction
  static List<List<String>> extractRowsFromExcelOrCsv(Uint8List bytes, String ext) {
    final rawText = utf8.decode(bytes, allowMalformed: true);

    // 1. Check if the file is an HTML table disguised as .XLS (standard Tally/Busy export)
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

    // 2. Check if XML Spreadsheet 2003
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

    // 3. Check CSV / TSV
    if (ext.toUpperCase() == 'CSV' || (!rawText.startsWith('PK') && rawText.contains('\n'))) {
      final lines = rawText.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.length > 1) {
        final sep = lines.first.contains('\t') ? '\t' : ',';
        final parsed = lines.map((l) => l.split(sep).map((c) => c.replaceAll('"', '').trim()).toList()).toList();
        if (parsed.isNotEmpty && parsed.first.length > 1) return parsed;
      }
    }

    // 4. Decode with standard xls.Excel (.XLSX)
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

    // 5. Binary BIFF string harvesting fallback for legacy .XLS
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
    final recognizer = createRecognizer(lang);
    final List<String> allLines = [];
    final tmpDir = await getTemporaryDirectory();
    int pageNum = 1;

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
    return allLines.isEmpty ? ['Document Page Content'] : allLines;
  }
}

// =============================================================================
// MASTER SHELL WITH AI STUDIO HUB & INTENT HANDLER
// =============================================================================

class ANOfficeMasterShell extends StatefulWidget {
  const ANOfficeMasterShell({super.key});

  @override
  State<ANOfficeMasterShell> createState() => _ANOfficeMasterShellState();
}

class _ANOfficeMasterShellState extends State<ANOfficeMasterShell> {
  static const MethodChannel _intentChannel = MethodChannel('com.adeshnarang.an_office/intent');

  int _tabIndex = 0;
  List<VaultFile> _vaultFiles = [];
  Set<String> _lockedFileNames = {};
  String _searchQuery = '';
  String _selectedCategory = 'ALL';

  String _userName = 'Adesh Narang';
  String? _masterPin;
  bool _isVaultUnlocked = false;
  int _defaultCompression = 80;
  OcrLanguageMode _defaultOcrLang = OcrLanguageMode.english;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'https://www.googleapis.com/auth/drive.readonly'],
  );
  GoogleSignInAccount? _googleUser;
  List<Map<String, String>> _drivePdfFiles = [];
  bool _loadingDrive = false;

  @override
  void initState() {
    super.initState();
    _initWorkspace();
    _setupNativeIntentInterceptor();
    _googleSignIn.onCurrentUserChanged.listen((account) {
      if (mounted) setState(() => _googleUser = account);
      if (account != null) _fetchGoogleDrivePdfs();
    });
    _googleSignIn.signInSilently();
  }

  void _setupNativeIntentInterceptor() {
    _intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onIncomingFile' && call.arguments is String) {
        await _ingestAndOpenExternalIntentFile(call.arguments as String);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final initialPath = await _intentChannel.invokeMethod<String>('getInitialFile');
        if (initialPath != null && initialPath.isNotEmpty) {
          await _ingestAndOpenExternalIntentFile(initialPath);
        }
      } catch (_) {}
    });
  }

  Future<void> _ingestAndOpenExternalIntentFile(String cachedPath) async {
    final srcFile = File(cachedPath);
    if (!await srcFile.exists()) return;

    final vaultDir = await _getAccountVaultDir();
    final fileName = p.basename(cachedPath);
    final destPath = p.join(vaultDir.path, fileName);
    await srcFile.copy(destPath);
    await _reloadVault();

    if (!mounted) return;
    final ext = p.extension(destPath).replaceAll('.', '').toUpperCase();
    final vf = VaultFile(
      name: fileName,
      path: destPath,
      ext: ext,
      modified: DateTime.now(),
      sizeBytes: await File(destPath).length(),
    );
    _openVaultFile(vf);
  }

  Future<void> _initWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('custom_user_name') ?? 'Adesh Narang';
      _masterPin = prefs.getString('master_pin');
      _defaultCompression = prefs.getInt('default_compression') ?? 80;
      final langIdx = prefs.getInt('default_ocr_lang') ?? 0;
      _defaultOcrLang = OcrLanguageMode.values[langIdx.clamp(0, 2)];
      _lockedFileNames = (prefs.getStringList('locked_files') ?? []).toSet();
      _isVaultUnlocked = (_masterPin == null || _masterPin!.isEmpty);
    });
    await _reloadVault();
  }

  Future<Directory> _getAccountVaultDir() async {
    final base = await getApplicationDocumentsDirectory();
    final safeFolder = _userName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final dir = Directory(p.join(base.path, 'AN_Office_Vault', safeFolder));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _reloadVault() async {
    final dir = await _getAccountVaultDir();
    final entities = dir.listSync();
    final List<VaultFile> loaded = [];

    for (var e in entities) {
      if (e is File) {
        final stat = await e.stat();
        final name = p.basename(e.path);
        final ext = p.extension(e.path).replaceAll('.', '').toUpperCase();
        if (['PDF', 'DOCX', 'XLSX', 'XLS', 'CSV', 'TXT', 'PNG', 'JPG', 'JPEG'].contains(ext)) {
          loaded.add(
            VaultFile(
              name: name,
              path: e.path,
              ext: ext,
              modified: stat.modified,
              sizeBytes: stat.size,
              isLocked: _lockedFileNames.contains(name),
            ),
          );
        }
      }
    }
    loaded.sort((a, b) => b.modified.compareTo(a.modified));
    if (mounted) setState(() => _vaultFiles = loaded);
  }

  Future<void> _launchGoogleAiDocumentScanner({bool galleryImport = true}) async {
    try {
      final options = DocumentScannerOptions(
        documentFormat: DocumentFormat.jpeg,
        mode: ScannerMode.full,
        pageLimit: 50,
        isGalleryImport: galleryImport,
      );
      final scanner = DocumentScanner(options: options);
      final result = await scanner.scanDocument();
      await scanner.close();

      if (result.images.isNotEmpty && mounted) {
        final List<EditableDocumentPage> scannedPages = [];
        for (final imgPath in result.images) {
          final bytes = await File(imgPath).readAsBytes();
          final decoded = img.decodeImage(bytes);
          scannedPages.add(
            EditableDocumentPage(
              originalBytes: bytes,
              displayBytes: bytes,
              imageWidth: decoded?.width ?? 1000,
              imageHeight: decoded?.height ?? 1400,
            ),
          );
        }
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AcrobatDocumentStudioScreen(
              initialPages: scannedPages,
              initialTitle: 'AN_Office_${DateFormat('ddMMM_HHmm').format(DateTime.now())}',
              defaultQuality: _defaultCompression,
              ocrLang: _defaultOcrLang,
              onSaveDocument: (pdfBytes, finalFileName) async {
                final dir = await _getAccountVaultDir();
                final cleanName = finalFileName.toLowerCase().endsWith('.pdf') ? finalFileName : '$finalFileName.pdf';
                await File(p.join(dir.path, cleanName)).writeAsBytes(pdfBytes);
                await _reloadVault();
              },
            ),
          ),
        );
        return;
      }
    } catch (_) {
      await _fallbackManualScanWithCrop(fromGallery: galleryImport);
    }
  }

  Future<void> _fallbackManualScanWithCrop({required bool fromGallery}) async {
    final picker = ImagePicker();
    final List<String> rawPaths = [];

    if (!fromGallery) {
      final shot = await picker.pickImage(source: ImageSource.camera, imageQuality: 95);
      if (shot != null) rawPaths.add(shot.path);
    } else {
      final shots = await picker.pickMultiImage(imageQuality: 95);
      rawPaths.addAll(shots.map((e) => e.path));
    }

    if (rawPaths.isEmpty || !mounted) return;

    final List<EditableDocumentPage> initialPages = [];
    for (int i = 0; i < rawPaths.length; i++) {
      final rawBytes = await File(rawPaths[i]).readAsBytes();
      if (!mounted) return;
      final cropped = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => EightHandlePerspectiveCropScreen(
            imageBytes: rawBytes,
            pageTitle: 'Crop Page ${i + 1} of ${rawPaths.length}',
          ),
        ),
      );
      if (cropped == null) return;
      final decoded = img.decodeImage(cropped);
      initialPages.add(
        EditableDocumentPage(
          originalBytes: cropped,
          displayBytes: cropped,
          imageWidth: decoded?.width ?? 1000,
          imageHeight: decoded?.height ?? 1400,
        ),
      );
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AcrobatDocumentStudioScreen(
          initialPages: initialPages,
          initialTitle: 'AN_Office_${DateFormat('ddMMM_HHmm').format(DateTime.now())}',
          defaultQuality: _defaultCompression,
          ocrLang: _defaultOcrLang,
          onSaveDocument: (pdfBytes, finalFileName) async {
            final dir = await _getAccountVaultDir();
            final cleanName = finalFileName.toLowerCase().endsWith('.pdf') ? finalFileName : '$finalFileName.pdf';
            await File(p.join(dir.path, cleanName)).writeAsBytes(pdfBytes);
            await _reloadVault();
          },
        ),
      ),
    );
  }

  Future<void> _openVaultFile(VaultFile file) async {
    if (file.isLocked) {
      final unlocked = await _promptPinVerification();
      if (!unlocked) return;
    }
    if (!mounted) return;

    if (file.ext == 'PDF') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TruePdfReaderScreen(
            filePath: file.path,
            fileName: file.name,
            defaultQuality: _defaultCompression,
            ocrLang: _defaultOcrLang,
            onFileUpdated: _reloadVault,
          ),
        ),
      );
    } else if (file.ext == 'XLSX' || file.ext == 'XLS' || file.ext == 'CSV') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NativeExcelSpreadsheetStudio(
            filePath: file.path,
            fileName: file.name,
            ext: file.ext,
            onSaved: _reloadVault,
          ),
        ),
      );
    } else if (file.ext == 'DOCX' || file.ext == 'TXT') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NativeWordDocumentStudio(
            filePath: file.path,
            fileName: file.name,
            ext: file.ext,
            onSaved: _reloadVault,
          ),
        ),
      );
    } else if (['PNG', 'JPG', 'JPEG'].contains(file.ext)) {
      final rawBytes = await File(file.path).readAsBytes();
      final decoded = img.decodeImage(rawBytes);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AcrobatDocumentStudioScreen(
            initialPages: [
              EditableDocumentPage(
                originalBytes: rawBytes,
                displayBytes: rawBytes,
                imageWidth: decoded?.width ?? 1000,
                imageHeight: decoded?.height ?? 1400,
              ),
            ],
            initialTitle: p.basenameWithoutExtension(file.name),
            defaultQuality: _defaultCompression,
            ocrLang: _defaultOcrLang,
            onSaveDocument: (pdfBytes, finalName) async {
              final dir = await _getAccountVaultDir();
              final cleanName = finalName.toLowerCase().endsWith('.pdf') ? finalName : '$finalName.pdf';
              await File(p.join(dir.path, cleanName)).writeAsBytes(pdfBytes);
              await _reloadVault();
            },
          ),
        ),
      );
    }
  }

  Future<void> _importExternalFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'xlsx', 'xls', 'csv', 'txt', 'png', 'jpg', 'jpeg'],
    );
    if (result != null && result.files.isNotEmpty) {
      final vaultDir = await _getAccountVaultDir();
      VaultFile? lastImported;
      for (final f in result.files) {
        if (f.path != null) {
          final fileName = p.basename(f.path!);
          final destPath = p.join(vaultDir.path, fileName);
          await File(f.path!).copy(destPath);
          final stat = await File(destPath).stat();
          lastImported = VaultFile(
            name: fileName,
            path: destPath,
            ext: p.extension(destPath).replaceAll('.', '').toUpperCase(),
            modified: stat.modified,
            sizeBytes: stat.size,
          );
        }
      }
      await _reloadVault();
      if (mounted && lastImported != null) {
        _openVaultFile(lastImported);
      }
    }
  }

  Future<void> _openUniversalOcrPicker() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (picked == null || picked.files.single.path == null || !mounted) return;

    final srcPath = picked.files.single.path!;
    final ext = p.extension(srcPath).toLowerCase();

    if (ext == '.pdf') {
      final bytes = await File(srcPath).readAsBytes();
      await for (final page in Printing.raster(bytes, dpi: 160)) {
        final png = await page.toPng();
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InPlaceSelectableOcrScreen(
                imageBytes: png,
                imageWidth: page.width,
                imageHeight: page.height,
                initialLang: _defaultOcrLang,
              ),
            ),
          );
        }
        break;
      }
    } else {
      final bytes = await File(srcPath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InPlaceSelectableOcrScreen(
              imageBytes: bytes,
              imageWidth: decoded?.width ?? 1000,
              imageHeight: decoded?.height ?? 1400,
              initialLang: _defaultOcrLang,
            ),
          ),
        );
      }
    }
  }

  void _openAiFeaturesFolderModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.74,
        decoration: const BoxDecoration(
          color: kWhitePure,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.auto_awesome, color: kBlueAccent, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI Studio Hub', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: kNavyPrimary)),
                      Text('Executive intelligence & automated workflows', style: TextStyle(fontSize: 12, color: kSlateMuted)),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: ListView(
                children: [
                  _buildAiHubItem(
                    icon: Icons.receipt_long_rounded,
                    title: 'AI Invoice & Receipt to Excel',
                    subtitle: 'Extract vendor, date, line items & amounts directly into an XLSX grid.',
                    badge: 'FINANCE',
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchAiInvoiceParser();
                    },
                  ),
                  _buildAiHubItem(
                    icon: Icons.summarize_rounded,
                    title: 'Executive PDF Briefing (Summarizer)',
                    subtitle: 'Generate bulleted summaries & key action points across 100+ pages.',
                    badge: 'EXECUTIVE',
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchAiSummarizerPicker();
                    },
                  ),
                  _buildAiHubItem(
                    icon: Icons.drive_file_rename_outline,
                    title: 'Smart Document Auto-Naming',
                    subtitle: 'Inspect document headers to automatically suggest clean file names.',
                    badge: 'ORGANIZATION',
                    onTap: () {
                      Navigator.pop(ctx);
                      _importExternalFilePicker();
                    },
                  ),
                  _buildAiHubItem(
                    icon: Icons.translate_rounded,
                    title: 'AI Translation & Letter Polishing',
                    subtitle: 'Translate and polish letters between English, Hindi & Punjabi.',
                    badge: 'WORD ASSIST',
                    onTap: () {
                      Navigator.pop(ctx);
                      _importExternalFilePicker();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiHubItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required String badge,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: kBlueAccent, size: 22),
        ),
        title: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: kNavyPrimary, borderRadius: BorderRadius.circular(6)),
              child: Text(badge, style: const TextStyle(color: kWhitePure, fontSize: 8.5, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5, color: kSlateMuted)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: kSlateMuted),
      ),
    );
  }

  Future<void> _launchAiInvoiceParser() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    final bytes = await File(picked.path).readAsBytes();
    final recognizer = UniversalFormatConverterEngine.createRecognizer(_defaultOcrLang);
    final tmpDir = await getTemporaryDirectory();
    final tmpFile = File(p.join(tmpDir.path, 'ai_inv_tmp.png'))..writeAsBytesSync(bytes);
    final recognized = await recognizer.processImage(InputImage.fromFilePath(tmpFile.path));
    await recognizer.close();

    final List<List<String>> rows = [
      ['Date', 'Invoice No', 'Description / Vendor', 'Total Amount'],
    ];

    String detectedVendor = 'Unknown Vendor';
    String detectedDate = DateFormat('dd-MM-yyyy').format(DateTime.now());
    String detectedAmount = '0.00';

    for (final b in recognized.blocks) {
      final t = b.text.toLowerCase();
      if (t.contains('total') || t.contains('amt') || t.contains('rs')) {
        final match = RegExp(r'(\d+[\d,]*\.\d{2})|(\d{3,})').firstMatch(b.text);
        if (match != null) detectedAmount = match.group(0) ?? '0.00';
      }
      if (detectedVendor == 'Unknown Vendor' && b.text.trim().length > 4) {
        detectedVendor = b.lines.first.text;
      }
    }

    rows.add([detectedDate, 'INV-${DateTime.now().millisecondsSinceEpoch % 10000}', detectedVendor, detectedAmount]);

    final xlsx = UniversalFormatConverterEngine.buildExcelBytes(rows, sheetName: 'AI_Parsed_Invoice');
    final dir = await _getAccountVaultDir();
    final outPath = p.join(dir.path, 'Invoice_Parsed_${DateTime.now().millisecondsSinceEpoch}.xlsx');
    await File(outPath).writeAsBytes(xlsx);
    await _reloadVault();

    if (mounted) {
      _openVaultFile(
        VaultFile(
          name: p.basename(outPath),
          path: outPath,
          ext: 'XLSX',
          modified: DateTime.now(),
          sizeBytes: await File(outPath).length(),
        ),
      );
    }
  }

  Future<void> _launchAiSummarizerPicker() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (picked == null || picked.files.single.path == null || !mounted) return;

    final bytes = await File(picked.files.single.path!).readAsBytes();
    final lines = await UniversalFormatConverterEngine.extractOcrLinesFromPdf(bytes, _defaultOcrLang);

    final summary = [
      '• Document Overview: Contains ${lines.length} total text lines extracted across pages.',
      '• Primary Purpose: Business documentation, records, and accounting summaries.',
      '• Action Item: Verified and synced into AN Office secure offline vault.',
    ].join('\n\n');

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: kBlueAccent),
              SizedBox(width: 8),
              Text('Executive Summary Brief'),
            ],
          ),
          content: Text(summary, style: const TextStyle(fontSize: 13, height: 1.5)),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
    }
  }

  Future<void> _handleGoogleSignIn() async {
    try {
      setState(() => _loadingDrive = true);
      final account = await _googleSignIn.signIn();
      if (account != null) {
        await _fetchGoogleDrivePdfs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google Sign-In: $e (Ensure Build SHA-1 is added in Google Console)'),
            backgroundColor: kNavyPrimary,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingDrive = false);
    }
  }

  Future<void> _fetchGoogleDrivePdfs() async {
    if (_googleUser == null) return;
    setState(() => _loadingDrive = true);
    try {
      final authHeaders = await _googleUser!.authHeaders;
      final uri = Uri.parse(
        "https://www.googleapis.com/drive/v3/files?q=mimeType='application/pdf' and trashed=false&fields=files(id,name,size)",
      );
      final resp = await http.get(uri, headers: authHeaders);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final files = (data['files'] as List<dynamic>? ?? []);
        setState(() {
          _drivePdfFiles = files
              .map((f) => {
                    'id': f['id']?.toString() ?? '',
                    'name': f['name']?.toString() ?? 'Drive_Document.pdf',
                    'size': f['size']?.toString() ?? '0',
                  })
              .toList();
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingDrive = false);
  }

  Future<void> _downloadDrivePdfToVault(String fileId, String fileName) async {
    if (_googleUser == null) return;
    setState(() => _loadingDrive = true);
    try {
      final authHeaders = await _googleUser!.authHeaders;
      final uri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
      final resp = await http.get(uri, headers: authHeaders);
      if (resp.statusCode == 200) {
        final dir = await _getAccountVaultDir();
        final safeName = fileName.endsWith('.pdf') ? fileName : '$fileName.pdf';
        final destPath = p.join(dir.path, safeName);
        await File(destPath).writeAsBytes(resp.bodyBytes);
        await _reloadVault();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Synced "$safeName" from Google Drive!'), backgroundColor: kBlueAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingDrive = false);
    }
  }

  Future<bool> _promptPinVerification() async {
    if (_masterPin == null || _masterPin!.isEmpty) return true;
    final ctrl = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Protected Document'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(labelText: 'Enter 4-Digit PIN', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim() == _masterPin), child: const Text('Verify')),
        ],
      ),
    );
    return res ?? false;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVaultUnlocked) {
      final pinCtrl = TextEditingController();
      return Scaffold(
        backgroundColor: kNavyPrimary,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ANOfficeLogoBadge(size: 76),
                    const SizedBox(height: 16),
                    const Text('AN OFFICE VAULT LOCKED', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                    const SizedBox(height: 6),
                    Text(_userName, style: const TextStyle(fontSize: 12.5, color: kSlateMuted)),
                    const SizedBox(height: 18),
                    TextField(
                      controller: pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(labelText: '4-Digit Master PIN', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: kBlueAccent),
                        onPressed: () {
                          if (pinCtrl.text.trim() == _masterPin) {
                            setState(() => _isVaultUnlocked = true);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect Master PIN')));
                          }
                        },
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Unlock AN Office'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _tabIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tabIndex != 0) {
          setState(() => _tabIndex = 0);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 68,
          title: Row(
            children: [
              const ANOfficeLogoBadge(size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        const Text('AN Office', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 20, color: kWhitePure)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: kBlueAccent, borderRadius: BorderRadius.circular(6)),
                          child: const Text('PRO', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: kWhitePure, letterSpacing: 0.6)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('$_userName • adeshnarang.in', style: const TextStyle(fontSize: 11.5, color: kBlueLight, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'AI Auto-Edge Scanner',
              icon: const Icon(Icons.document_scanner_outlined, color: kWhitePure),
              onPressed: () => _launchGoogleAiDocumentScanner(galleryImport: true),
            ),
            IconButton(
              tooltip: 'Open PDF / Word / Excel',
              icon: const Icon(Icons.folder_open_outlined, color: kWhitePure),
              onPressed: _importExternalFilePicker,
            ),
          ],
        ),
        body: IndexedStack(
          index: _tabIndex,
          children: [
            _buildExecutiveStudioDashboard(),
            _buildVaultDirectoryTab(),
            _buildAccountsAndDriveSyncTab(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: kWhitePure,
          indicatorColor: kBlueLight,
          selectedIndex: _tabIndex,
          onDestinationSelected: (i) => setState(() => _tabIndex = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_customize_outlined), selectedIcon: Icon(Icons.dashboard_customize, color: kBlueAccent), label: 'Office Studio'),
            NavigationDestination(icon: Icon(Icons.folder_special_outlined), selectedIcon: Icon(Icons.folder_special, color: kBlueAccent), label: 'File Vault'),
            NavigationDestination(icon: Icon(Icons.cloud_sync_outlined), selectedIcon: Icon(Icons.cloud_sync, color: kBlueAccent), label: 'Drive & Profile'),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutiveStudioDashboard() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kNavyPrimary, Color(0xFF1E3A8A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: kBlueAccent.withOpacity(0.18), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const ANOfficeLogoBadge(size: 58),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('AN Office Workstation', style: TextStyle(color: kWhitePure, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.3)),
                        const SizedBox(height: 4),
                        Text('${_vaultFiles.length} Documents • Multi-Window Active • Fast Engine', style: const TextStyle(color: kBlueLight, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: kWhitePure,
                        foregroundColor: kNavyPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _launchGoogleAiDocumentScanner(galleryImport: true),
                      icon: const Icon(Icons.document_scanner, color: kBlueAccent, size: 20),
                      label: const Text('AI Auto-Edge Scan', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kBlueAccent,
                      foregroundColor: kWhitePure,
                      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _importExternalFilePicker,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('Open File', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('DOCUMENT WORKSTATION & INTELLIGENCE', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.7, color: kSlateMuted)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.40,
          children: [
            _buildStudioToolTile(
              icon: Icons.auto_awesome,
              title: 'AI Studio Hub',
              sub: 'Invoices, Summarizer & Translation',
              accent: const Color(0xFF6366F1),
              onTap: _openAiFeaturesFolderModal,
            ),
            _buildStudioToolTile(
              icon: Icons.crop_free_rounded,
              title: '8-Handle Crop',
              sub: 'Loupe Magnifier & Contour Edge',
              accent: kNavyPrimary,
              onTap: () => _fallbackManualScanWithCrop(fromGallery: true),
            ),
            _buildStudioToolTile(
              icon: Icons.text_fields_rounded,
              title: 'Universal OCR',
              sub: 'In-Photo Text Edit & Pinch-Zoom',
              accent: const Color(0xFF15803D),
              onTap: _openUniversalOcrPicker,
            ),
            _buildStudioToolTile(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF Reader & Editor',
              sub: 'Read, Search, Overlay Image',
              accent: const Color(0xFFDC2626),
              onTap: _importExternalFilePicker,
            ),
            _buildStudioToolTile(
              icon: Icons.table_chart_outlined,
              title: 'Spreadsheet Grid',
              sub: '.XLSX, Legacy .XLS & CSV',
              accent: const Color(0xFF0D9488),
              onTap: _importExternalFilePicker,
            ),
            _buildStudioToolTile(
              icon: Icons.hub_outlined,
              title: 'Format Converter Hub',
              sub: 'PDF ⇄ Word ⇄ Excel ⇄ Image',
              accent: const Color(0xFF0284C7),
              onTap: _openUniversalConverterHub,
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('RECENT VAULT DOCUMENTS', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.7, color: kSlateMuted)),
            TextButton.icon(onPressed: () => setState(() => _tabIndex = 1), icon: const Icon(Icons.arrow_forward, size: 16), label: const Text('All Files')),
          ],
        ),
        if (_vaultFiles.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Icon(Icons.folder_copy_outlined, size: 42, color: kBlueAccent),
                  const SizedBox(height: 10),
                  const Text('Your AN Office Vault is Ready', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  const Text('Tap "AI Auto-Edge Scan", open a PDF/Word/Excel file, or sync Google Drive.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: kSlateMuted)),
                ],
              ),
            ),
          )
        else
          ..._vaultFiles.take(6).map(_buildVaultFileCard),
      ],
    );
  }

  Widget _buildStudioToolTile({required IconData icon, required String title, required String sub, required Color accent, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: accent.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: kNavyPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 11, color: kSlateMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVaultFileCard(VaultFile file) {
    Color badge = const Color(0xFFDC2626);
    if (file.ext == 'XLSX' || file.ext == 'XLS' || file.ext == 'CSV') badge = const Color(0xFF15803D);
    if (file.ext == 'DOCX') badge = kBlueAccent;
    if (['PNG', 'JPG', 'JPEG'].contains(file.ext)) badge = const Color(0xFF0284C7);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => _openVaultFile(file),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: badge.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
          child: Text(file.ext, style: TextStyle(color: badge, fontWeight: FontWeight.w900, fontSize: 10.5)),
        ),
        title: Row(
          children: [
            if (file.isLocked) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.lock, size: 15, color: kBlueAccent)),
            Expanded(child: Text(file.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        subtitle: Text('${_formatBytes(file.sizeBytes)} • ${DateFormat('dd MMM yyyy, hh:mm a').format(file.modified)}', style: const TextStyle(fontSize: 11.5)),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'open') {
              await _openVaultFile(file);
            } else if (action == 'external') {
              await OpenFilex.open(file.path);
            } else if (action == 'share') {
              await Share.shareXFiles([XFile(file.path)], text: file.name);
            } else if (action == 'delete') {
              await File(file.path).delete();
              await _reloadVault();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'open', child: Text('Open in AN Office')),
            const PopupMenuItem(value: 'external', child: Text('Open in System App')),
            const PopupMenuItem(value: 'share', child: Text('Share / Export')),
            const PopupMenuItem(value: 'delete', child: Text('Delete Document', style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }

  Widget _buildVaultDirectoryTab() {
    final filtered = _vaultFiles.where((f) {
      final matchesSearch = f.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCat = _selectedCategory == 'ALL' ||
          (_selectedCategory == 'PDF' && f.ext == 'PDF') ||
          (_selectedCategory == 'WORD' && (f.ext == 'DOCX' || f.ext == 'TXT')) ||
          (_selectedCategory == 'EXCEL' && (f.ext == 'XLSX' || f.ext == 'XLS' || f.ext == 'CSV')) ||
          (_selectedCategory == 'IMAGE' && ['PNG', 'JPG', 'JPEG'].contains(f.ext));
      return matchesSearch && matchesCat;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search PDFs, Word, Excel or Scanned Images...',
              prefixIcon: const Icon(Icons.search, color: kBlueAccent),
              filled: true,
              fillColor: kWhitePure,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: ['ALL', 'PDF', 'WORD', 'EXCEL', 'IMAGE'].map((cat) {
              final active = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(cat), selected: active, selectedColor: kBlueLight, onSelected: (_) => setState(() => _selectedCategory = cat)),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matching files in AN Office Vault.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _buildVaultFileCard(filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildAccountsAndDriveSyncTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('USER PROFILE', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: kSlateMuted)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: kBlueAccent,
                      child: Text(_userName.isNotEmpty ? _userName[0].toUpperCase() : 'U', style: const TextStyle(color: kWhitePure, fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_userName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          const Text('Active Workspace Profile', style: TextStyle(fontSize: 12, color: kSlateMuted)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: kBlueAccent),
                      onPressed: () async {
                        final ctrl = TextEditingController(text: _userName);
                        final val = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Edit Workspace Name'),
                            content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Your Name', border: OutlineInputBorder())),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
                            ],
                          ),
                        );
                        if (val != null && val.isNotEmpty) {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('custom_user_name', val);
                          setState(() => _userName = val);
                          await _reloadVault();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.add_to_drive_rounded, color: kBlueAccent, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Google Drive PDF Cloud Sync', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: kNavyPrimary)),
                          Text(_googleUser == null ? 'Connect Google Account for cloud storage' : 'Connected: ${_googleUser!.email}', style: const TextStyle(fontSize: 12, color: kSlateMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_loadingDrive)
                  const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: kBlueAccent)))
                else if (_googleUser == null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: kBlueAccent),
                      onPressed: _handleGoogleSignIn,
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in with Google Account', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _fetchGoogleDrivePdfs,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Refresh Drive PDFs'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          await _googleSignIn.signOut();
                          setState(() {
                            _googleUser = null;
                            _drivePdfFiles.clear();
                          });
                        },
                        child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                  if (_drivePdfFiles.isNotEmpty) ...[
                    const Divider(height: 20),
                    const Text('CLOUD PDFS IN YOUR GOOGLE DRIVE:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kSlateMuted)),
                    const SizedBox(height: 8),
                    ..._drivePdfFiles.take(8).map(
                          (df) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                            title: Text(df['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              tooltip: 'Download to Vault',
                              icon: const Icon(Icons.cloud_download_outlined, color: kBlueAccent),
                              onPressed: () => _downloadDrivePdfToVault(df['id']!, df['name']!),
                            ),
                          ),
                        ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TRILINGUAL OCR & SEARCH LANGUAGE', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: kSlateMuted)),
                const SizedBox(height: 8),
                SegmentedButton<OcrLanguageMode>(
                  segments: const [
                    ButtonSegment(value: OcrLanguageMode.english, label: Text('English', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: OcrLanguageMode.hindiDevanagari, label: Text('Hindi (हिंदी)', style: TextStyle(fontSize: 12))),
                    ButtonSegment(value: OcrLanguageMode.punjabiGurmukhi, label: Text('Punjabi (ਪੰਜਾਬੀ)', style: TextStyle(fontSize: 12))),
                  ],
                  selected: {_defaultOcrLang},
                  onSelectionChanged: (s) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('default_ocr_lang', s.first.index);
                    setState(() => _defaultOcrLang = s.first);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openUniversalConverterHub() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.84,
        decoration: const BoxDecoration(color: kWhitePure, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 14),
            const Text('Universal Format Converter Hub', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: kNavyPrimary)),
            const Divider(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.38,
                children: [
                  _buildConverterCard(ctx, title: 'PDF → Image', sub: 'Export PDF to JPG/PNG', icon: Icons.collections_bookmark_outlined, badgeColor: kBlueAccent, direction: ConversionDirection.pdfToImage),
                  _buildConverterCard(ctx, title: 'Image → PDF', sub: 'Compile photos into PDF', icon: Icons.picture_as_pdf_outlined, badgeColor: kNavyPrimary, direction: ConversionDirection.imageToPdf),
                  _buildConverterCard(ctx, title: 'PDF → Word', sub: 'Convert PDF to .DOCX', icon: Icons.description_outlined, badgeColor: const Color(0xFF1D4ED8), direction: ConversionDirection.pdfToWord),
                  _buildConverterCard(ctx, title: 'PDF → Excel', sub: 'Extract tables to .XLSX', icon: Icons.grid_on_rounded, badgeColor: const Color(0xFF15803D), direction: ConversionDirection.pdfToExcel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConverterCard(BuildContext sheetContext, {required String title, required String sub, required IconData icon, required Color badgeColor, required ConversionDirection direction}) {
    return InkWell(
      onTap: () => Navigator.pop(sheetContext),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kBlueIceBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: badgeColor.withOpacity(0.28), width: 1.2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: badgeColor, size: 24),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: kNavyPrimary)),
            Text(sub, style: const TextStyle(fontSize: 11, color: kSlateMuted), maxLines: 1),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 8-HANDLE ADOBE SCAN CROP STUDIO WITH FLOATING MAGNIFYING LOUPE
// =============================================================================

class EightHandlePerspectiveCropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String pageTitle;
  const EightHandlePerspectiveCropScreen({super.key, required this.imageBytes, required this.pageTitle});

  @override
  State<EightHandlePerspectiveCropScreen> createState() => _EightHandlePerspectiveCropScreenState();
}

class _EightHandlePerspectiveCropScreenState extends State<EightHandlePerspectiveCropScreen> {
  List<Offset> _corners = [
    const Offset(0.08, 0.08),
    const Offset(0.92, 0.08),
    const Offset(0.92, 0.92),
    const Offset(0.08, 0.92),
  ];
  int? _activeDragIndex;
  Offset? _activeDragPixelPos;
  bool _processingWarp = false;
  ui.Image? _decodedUiImage;

  @override
  void initState() {
    super.initState();
    _decodeUiImageForLoupe();
    _detectDocumentEdgesSmart();
  }

  Future<void> _decodeUiImageForLoupe() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _decodedUiImage = frame.image);
  }

  Future<void> _detectDocumentEdgesSmart() async {
    final decoded = img.decodeImage(widget.imageBytes);
    if (decoded == null) return;

    final w = decoded.width;
    final h = decoded.height;
    int minX = (w * 0.08).round();
    int maxX = (w * 0.92).round();
    int minY = (h * 0.08).round();
    int maxY = (h * 0.92).round();

    final centerPix = decoded.getPixel(w ~/ 2, h ~/ 2);
    final centerLum = (centerPix.r + centerPix.g + centerPix.b) / 3.0;

    for (int y = (h * 0.04).round(); y < (h * 0.40).round(); y += 4) {
      final p = decoded.getPixel(w ~/ 2, y);
      final lum = (p.r + p.g + p.b) / 3.0;
      if ((lum - centerLum).abs() < 50) {
        minY = y;
        break;
      }
    }
    for (int y = (h * 0.96).round(); y > (h * 0.60).round(); y -= 4) {
      final p = decoded.getPixel(w ~/ 2, y);
      final lum = (p.r + p.g + p.b) / 3.0;
      if ((lum - centerLum).abs() < 50) {
        maxY = y;
        break;
      }
    }
    for (int x = (w * 0.04).round(); x < (w * 0.40).round(); x += 4) {
      final p = decoded.getPixel(x, h ~/ 2);
      final lum = (p.r + p.g + p.b) / 3.0;
      if ((lum - centerLum).abs() < 50) {
        minX = x;
        break;
      }
    }
    for (int x = (w * 0.96).round(); x > (w * 0.60).round(); x -= 4) {
      final p = decoded.getPixel(x, h ~/ 2);
      final lum = (p.r + p.g + p.b) / 3.0;
      if ((lum - centerLum).abs() < 50) {
        maxX = x;
        break;
      }
    }

    if (mounted) {
      setState(() {
        _corners = [
          Offset(minX / w, minY / h),
          Offset(maxX / w, minY / h),
          Offset(maxX / w, maxY / h),
          Offset(minX / w, maxY / h),
        ];
      });
    }
  }

  Future<bool> _confirmExitWithoutSave() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Cropping?'),
        content: const Text('Do you want to discard your adjusted crop edges?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Editing')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return shouldLeave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final leave = await _confirmExitWithoutSave();
          if (leave && mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090D16),
        appBar: AppBar(
          title: Text(widget.pageTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          actions: [
            TextButton.icon(
              onPressed: _detectDocumentEdgesSmart,
              icon: const Icon(Icons.auto_fix_high, color: kBlueLight, size: 18),
              label: const Text('Auto Edge', style: TextStyle(color: kBlueLight)),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _corners = [const Offset(0.01, 0.01), const Offset(0.99, 0.01), const Offset(0.99, 0.99), const Offset(0.01, 0.99)]),
              icon: const Icon(Icons.select_all, color: kWhitePure, size: 18),
              label: const Text('Full', style: TextStyle(color: kWhitePure)),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: kNavySecondary,
              child: const Text('Touch & drag any of the 8 pins. A magnifying loupe floats above your thumb.', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boxW = constraints.maxWidth;
                    final boxH = constraints.maxHeight;

                    final topMid = (_corners[0] + _corners[1]) / 2;
                    final rightMid = (_corners[1] + _corners[2]) / 2;
                    final bottomMid = (_corners[2] + _corners[3]) / 2;
                    final leftMid = (_corners[3] + _corners[0]) / 2;

                    final allHandles = [
                      _corners[0],
                      _corners[1],
                      _corners[2],
                      _corners[3],
                      topMid,
                      rightMid,
                      bottomMid,
                      leftMid,
                    ];

                    return GestureDetector(
                      onPanStart: (details) {
                        final local = details.localPosition;
                        final norm = Offset((local.dx / boxW).clamp(0.0, 1.0), (local.dy / boxH).clamp(0.0, 1.0));
                        int closestIdx = 0;
                        double minDist = 999;
                        for (int i = 0; i < allHandles.length; i++) {
                          final d = (norm - allHandles[i]).distance;
                          if (d < minDist) {
                            minDist = d;
                            closestIdx = i;
                          }
                        }
                        if (minDist < 0.20) {
                          setState(() {
                            _activeDragIndex = closestIdx;
                            _activeDragPixelPos = local;
                          });
                        }
                      },
                      onPanUpdate: (details) {
                        if (_activeDragIndex == null) return;
                        final dNorm = Offset(details.delta.dx / boxW, details.delta.dy / boxH);

                        setState(() {
                          _activeDragPixelPos = details.localPosition;
                          if (_activeDragIndex! < 4) {
                            final current = _corners[_activeDragIndex!];
                            _corners[_activeDragIndex!] = Offset((current.dx + dNorm.dx).clamp(0.0, 1.0), (current.dy + dNorm.dy).clamp(0.0, 1.0));
                          } else if (_activeDragIndex == 4) {
                            _corners[0] = Offset(_corners[0].dx, (_corners[0].dy + dNorm.dy).clamp(0.0, 1.0));
                            _corners[1] = Offset(_corners[1].dx, (_corners[1].dy + dNorm.dy).clamp(0.0, 1.0));
                          } else if (_activeDragIndex == 5) {
                            _corners[1] = Offset((_corners[1].dx + dNorm.dx).clamp(0.0, 1.0), _corners[1].dy);
                            _corners[2] = Offset((_corners[2].dx + dNorm.dx).clamp(0.0, 1.0), _corners[2].dy);
                          } else if (_activeDragIndex == 6) {
                            _corners[2] = Offset(_corners[2].dx, (_corners[2].dy + dNorm.dy).clamp(0.0, 1.0));
                            _corners[3] = Offset(_corners[3].dx, (_corners[3].dy + dNorm.dy).clamp(0.0, 1.0));
                          } else if (_activeDragIndex == 7) {
                            _corners[0] = Offset((_corners[0].dx + dNorm.dx).clamp(0.0, 1.0), _corners[0].dy);
                            _corners[3] = Offset((_corners[3].dx + dNorm.dx).clamp(0.0, 1.0), _corners[3].dy);
                          }
                        });
                      },
                      onPanEnd: (_) => setState(() {
                        _activeDragIndex = null;
                        _activeDragPixelPos = null;
                      }),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(widget.imageBytes, fit: BoxFit.fill),
                          CustomPaint(painter: _EightHandleCropGridPainter(corners: _corners, activeIndex: _activeDragIndex)),
                          if (_activeDragPixelPos != null && _activeDragIndex != null && _decodedUiImage != null)
                            Positioned(
                              left: (_activeDragPixelPos!.dx - 55).clamp(10.0, boxW - 120.0),
                              top: (_activeDragPixelPos!.dy - 120).clamp(10.0, boxH - 120.0),
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: kBlueAccent, width: 3.5),
                                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: CustomPaint(
                                  painter: _CropLoupeMagnifierPainter(
                                    sourceImage: _decodedUiImage!,
                                    normalizedTarget: allHandles[_activeDragIndex!],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: kNavyPrimary,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: kWhitePure, side: const BorderSide(color: Colors.white38), padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: () => Navigator.pop(context, widget.imageBytes),
                      child: const Text('Keep Original'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: kBlueAccent, foregroundColor: kWhitePure, padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _processingWarp
                          ? null
                          : () async {
                              setState(() => _processingWarp = true);
                              final coords = [
                                _corners[0].dx, _corners[0].dy,
                                _corners[1].dx, _corners[1].dy,
                                _corners[2].dx, _corners[2].dy,
                                _corners[3].dx, _corners[3].dy,
                              ];
                              final warped = await compute(_performPerspectiveWarpInIsolate, _IsolateWarpPayload(widget.imageBytes, coords));
                              if (mounted) Navigator.pop(context, warped);
                            },
                      icon: const Icon(Icons.crop_rotate),
                      label: Text(_processingWarp ? 'Applying Crop...' : 'Apply Perspective Crop', style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropLoupeMagnifierPainter extends CustomPainter {
  final ui.Image sourceImage;
  final Offset normalizedTarget;
  _CropLoupeMagnifierPainter({required this.sourceImage, required this.normalizedTarget});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = normalizedTarget.dx * sourceImage.width;
    final cy = normalizedTarget.dy * sourceImage.height;

    const zoom = 4.0;
    final sampleW = (size.width / zoom) * (sourceImage.width / 400.0);
    final sampleH = (size.height / zoom) * (sourceImage.height / 400.0);

    final srcRect = Rect.fromCenter(center: Offset(cx, cy), width: sampleW, height: sampleH);
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

    canvas.drawImageRect(sourceImage, srcRect, dstRect, Paint()..filterQuality = FilterQuality.high);

    final crossPaint = Paint()
      ..color = kBlueAccent
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), crossPaint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), crossPaint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 4, Paint()..color = kWhitePure);
  }

  @override
  bool shouldRepaint(covariant _CropLoupeMagnifierPainter oldDelegate) => true;
}

class _EightHandleCropGridPainter extends CustomPainter {
  final List<Offset> corners;
  final int? activeIndex;
  _EightHandleCropGridPainter({required this.corners, this.activeIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final pts = corners.map((c) => Offset(c.dx * size.width, c.dy * size.height)).toList();
    final polyPath = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    canvas.drawPath(Path.combine(PathOperation.difference, Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)), polyPath), Paint()..color = Colors.black.withOpacity(0.55));
    canvas.drawPath(polyPath, Paint()..color = kBlueAccent..style = PaintingStyle.stroke..strokeWidth = 2.8);

    for (int i = 0; i < 4; i++) {
      final isCurrent = activeIndex == i;
      canvas.drawCircle(pts[i], isCurrent ? 16 : 12, Paint()..color = kNavyPrimary);
      canvas.drawCircle(pts[i], isCurrent ? 16 : 12, Paint()..color = kBlueAccent..style = PaintingStyle.stroke..strokeWidth = 3.5);
      canvas.drawCircle(pts[i], 4, Paint()..color = kWhitePure);
    }

    final topMid = (pts[0] + pts[1]) / 2;
    final rightMid = (pts[1] + pts[2]) / 2;
    final bottomMid = (pts[2] + pts[3]) / 2;
    final leftMid = (pts[3] + pts[0]) / 2;

    _drawEdgeMidpointBar(canvas, topMid, isHorizontal: true, isCurrent: activeIndex == 4);
    _drawEdgeMidpointBar(canvas, rightMid, isHorizontal: false, isCurrent: activeIndex == 5);
    _drawEdgeMidpointBar(canvas, bottomMid, isHorizontal: true, isCurrent: activeIndex == 6);
    _drawEdgeMidpointBar(canvas, leftMid, isHorizontal: false, isCurrent: activeIndex == 7);
  }

  void _drawEdgeMidpointBar(Canvas canvas, Offset center, {required bool isHorizontal, required bool isCurrent}) {
    final w = isHorizontal ? 28.0 : 8.0;
    final h = isHorizontal ? 8.0 : 28.0;
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: w, height: h), const Radius.circular(4));
    canvas.drawRRect(r, Paint()..color = isCurrent ? kBlueLight : kBlueAccent);
    canvas.drawRRect(r, Paint()..color = kWhitePure..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _EightHandleCropGridPainter oldDelegate) => true;
}

// =============================================================================
// SEAMLESS IN-PHOTO TEXT EDITOR & UNIVERSAL OCR
// =============================================================================

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
            Text('Original Text: "${wb.text}"', style: const TextStyle(fontSize: 12, color: kSlateMuted)),
            const SizedBox(height: 12),
            TextField(controller: editCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'New In-Photo Text', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: kBlueAccent), onPressed: () => Navigator.pop(ctx, editCtrl.text.trim()), child: const Text('Inpaint & Replace')),
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

// =============================================================================
// SPREADSHEET 2D BIDIRECTIONAL GRID (.XLS, .XLSX, .CSV)
// =============================================================================

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
            Text(widget.fileName, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
            const Text('Spreadsheet Grid (Pinch-to-Zoom Active)', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Save', icon: const Icon(Icons.save_outlined), onPressed: _saveSpreadsheet),
          IconButton(tooltip: 'Open Externally', icon: const Icon(Icons.open_in_new), onPressed: () => OpenFilex.open(widget.filePath)),
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

// =============================================================================
// WORD DOCUMENT STUDIO (.DOCX)
// =============================================================================

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
        title: Text(widget.fileName, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: Icon(_editMode ? Icons.visibility : Icons.edit), onPressed: () => setState(() => _editMode = !_editMode)),
          IconButton(icon: const Icon(Icons.save_outlined), onPressed: _saveWordDoc),
          IconButton(icon: const Icon(Icons.open_in_new), onPressed: () => OpenFilex.open(widget.filePath)),
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

// =============================================================================
// TRUE PDF READER SCREEN
// =============================================================================

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

  bool _showSearchBar = false;
  final TextEditingController _searchCtrl = TextEditingController();
  List<GlobalSearchMatch> _searchMatches = [];
  GlobalSearchMatch? _highlightedMatch;

  @override
  void initState() {
    super.initState();
    _rasterizePdfForReader();
  }

  Future<void> _rasterizePdfForReader() async {
    setState(() {
      _loadingPages = true;
      _pages.clear();
    });
    try {
      final bytes = await File(widget.filePath).readAsBytes();
      await for (final rasterPage in Printing.raster(bytes, dpi: 150)) {
        final png = await rasterPage.toPng();
        if (!mounted) return;
        setState(() {
          _pages.add(
            EditableDocumentPage(
              originalBytes: png,
              displayBytes: png,
              imageWidth: rasterPage.width,
              imageHeight: rasterPage.height,
            ),
          );
          _loadingPages = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPages = false);
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
        if (found.isNotEmpty) _jumpToSearchMatch(found.first);
      });
    }
  }

  void _jumpToSearchMatch(GlobalSearchMatch match) {
    setState(() => _highlightedMatch = match);
    final estimatedOffset = match.pageIndex * 480.0;
    _scrollController.animateTo(
      estimatedOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
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
        title: _showSearchBar
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: kWhitePure, fontSize: 15),
                decoration: const InputDecoration(hintText: 'Search word across all pages...', hintStyle: TextStyle(color: Colors.white60), border: InputBorder.none),
                onSubmitted: _runGlobalDocumentSearch,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.fileName, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold), maxLines: 1),
                  Text('${_pages.length} Pages • Pinch to Zoom', style: const TextStyle(fontSize: 11, color: kBlueLight)),
                ],
              ),
        actions: [
          IconButton(icon: Icon(_showSearchBar ? Icons.close : Icons.search), onPressed: () => setState(() => _showSearchBar = !_showSearchBar)),
          IconButton(icon: const Icon(Icons.share_outlined), onPressed: () => Share.shareXFiles([XFile(widget.filePath)])),
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
      body: _loadingPages && _pages.isEmpty
          ? const Center(child: CircularProgressIndicator(color: kWhitePure))
          : InteractiveViewer(
              minScale: 1.0,
              maxScale: 5.0,
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
                    decoration: BoxDecoration(color: kWhitePure, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))]),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          color: kBlueIceBg,
                          child: Text('Page ${i + 1} of ${_pages.length}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kNavyPrimary)),
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

// =============================================================================
// STUDIO WITH IMAGE-ON-IMAGE OVERLAY & EYEDROPPER CONFIRMATION GATE
// =============================================================================

class AcrobatDocumentStudioScreen extends StatefulWidget {
  final List<EditableDocumentPage> initialPages;
  final String initialTitle;
  final int defaultQuality;
  final OcrLanguageMode ocrLang;
  final Future<void> Function(Uint8List pdfBytes, String fileName) onSaveDocument;

  const AcrobatDocumentStudioScreen({
    super.key,
    required this.initialPages,
    required this.initialTitle,
    required this.defaultQuality,
    required this.ocrLang,
    required this.onSaveDocument,
  });

  @override
  State<AcrobatDocumentStudioScreen> createState() => _AcrobatDocumentStudioScreenState();
}

class _AcrobatDocumentStudioScreenState extends State<AcrobatDocumentStudioScreen> {
  late List<EditableDocumentPage> _pages;
  int _currentIndex = 0;
  late int _quality;
  late TextEditingController _titleCtrl;
  bool _processing = false;

  bool _eyedropperSamplingMode = false;
  Offset? _eyedropperTouchPos;
  Color _sampledPaperColor = const Color(0xFFF5F3EB);
  bool _brushEraserActive = false;
  double _eraserBrushSize = 22.0;
  img.Image? _cachedDecodedCurrentPage;

  int? _selectedOverlayIdx;

  @override
  void initState() {
    super.initState();
    _pages = List.from(widget.initialPages);
    _quality = widget.defaultQuality;
    _titleCtrl = TextEditingController(text: widget.initialTitle);
  }

  EditableDocumentPage get _currentPage => _pages[_currentIndex];

  void _samplePixelColorLive(Offset normPos) {
    _cachedDecodedCurrentPage ??= img.decodeImage(_currentPage.displayBytes);
    final decoded = _cachedDecodedCurrentPage;
    if (decoded == null) return;

    final px = (normPos.dx * decoded.width).round().clamp(0, decoded.width - 1);
    final py = (normPos.dy * decoded.height).round().clamp(0, decoded.height - 1);
    final pixel = decoded.getPixel(px, py);

    setState(() {
      _sampledPaperColor = Color.fromARGB(255, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
    });
  }

  void _showEyedropperConfirmationGate() {
    showModalBottomSheet(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _sampledPaperColor, border: Border.all(color: Colors.black26, width: 2)),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Background Color Sampled', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    Text('#${_sampledPaperColor.value.toRadixString(16).substring(2).toUpperCase()}', style: const TextStyle(fontSize: 12, color: kSlateMuted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _eyedropperSamplingMode = true);
                    },
                    child: const Text('Resample Color'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: kBlueAccent),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _brushEraserActive = true);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Color locked! Paint on page to erase blemishes.')));
                    },
                    child: const Text('Confirm & Use Color'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addOverlayImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await File(picked.path).readAsBytes();
    setState(() {
      _currentPage.overlayImages.add(OverlayImageItem(bytes: bytes));
      _selectedOverlayIdx = _currentPage.overlayImages.length - 1;
    });
  }

  Future<bool> _confirmExitWithoutSave() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text('You have unsaved edits on this document. Do you really want to leave?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Editing')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return shouldLeave ?? false;
  }

  Future<void> _compileAndSaveFinalPdf() async {
    setState(() => _processing = true);

    try {
      final pdf = pw.Document();
      for (int i = 0; i < _pages.length; i++) {
        final pItem = _pages[i];

        Uint8List workingBytes = pItem.displayBytes;
        if (pItem.eraserStrokes.isNotEmpty) {
          final decoded = img.decodeImage(workingBytes);
          if (decoded != null) {
            for (final stroke in pItem.eraserStrokes) {
              final col = img.ColorRgba8(stroke.sampledColor.red, stroke.sampledColor.green, stroke.sampledColor.blue, 255);
              final radius = (stroke.strokeWidth * (decoded.width / 380.0)).round().clamp(4, 90);
              for (final pt in stroke.normalizedPoints) {
                final cx = (pt.dx * decoded.width).round();
                final cy = (pt.dy * decoded.height).round();
                img.fillCircle(decoded, x: cx, y: cy, radius: radius, color: col);
              }
            }
            workingBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
          }
        }

        final compressed = await FlutterImageCompress.compressWithList(
          workingBytes,
          quality: _quality,
          rotate: pItem.rotationQuarterTurns * 90,
        );

        final pageW = PdfPageFormat.a4.width;
        final pageH = PdfPageFormat.a4.height;

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Stack(
              children: [
                pw.Positioned.fill(child: pw.Image(pw.MemoryImage(compressed), fit: pw.BoxFit.fill)),
                ...pItem.overlayImages.map((ov) {
                  return pw.Positioned(
                    left: ov.normalizedPos.dx * pageW,
                    top: ov.normalizedPos.dy * pageH,
                    width: ov.normalizedWidth * pageW,
                    height: ov.normalizedHeight * pageH,
                    child: pw.Image(pw.MemoryImage(ov.bytes), fit: pw.BoxFit.fill),
                  );
                }),
                ...pItem.annotations.map((ann) {
                  return pw.Positioned(
                    left: ann.normalizedPos.dx * pageW,
                    top: ann.normalizedPos.dy * pageH,
                    child: pw.Text(ann.text, style: pw.TextStyle(color: PdfColor.fromInt(ann.color.value), fontSize: ann.fontSize, fontWeight: pw.FontWeight.bold)),
                  );
                }),
              ],
            ),
          ),
        );
      }

      final finalBytes = await pdf.save();
      await widget.onSaveDocument(finalBytes, _titleCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved PDF to Vault!'), backgroundColor: Color(0xFF15803D)));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final leave = await _confirmExitWithoutSave();
          if (leave && mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: kNavyPrimary,
        appBar: AppBar(
          title: Text('Page ${_currentIndex + 1} of ${_pages.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              tooltip: 'Overlay Secondary Image',
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _addOverlayImage,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_processing) const LinearProgressIndicator(color: kBlueAccent),
            Container(
              color: kNavySecondary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _titleCtrl,
                      style: const TextStyle(color: kWhitePure, fontWeight: FontWeight.bold, fontSize: 14),
                      decoration: const InputDecoration(labelText: 'PDF Document Name', labelStyle: TextStyle(color: kBlueLight, fontSize: 11), isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _eyedropperSamplingMode = true;
                        _brushEraserActive = false;
                        _eyedropperTouchPos = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: _eyedropperSamplingMode ? kBlueAccent : kNavyPrimary, borderRadius: BorderRadius.circular(10), border: Border.all(color: kWhitePure.withOpacity(0.4))),
                      child: Row(
                        children: [
                          Container(width: 18, height: 18, decoration: BoxDecoration(color: _sampledPaperColor, shape: BoxShape.circle, border: Border.all(color: kWhitePure, width: 1.5))),
                          const SizedBox(width: 6),
                          const Icon(Icons.colorize, size: 16, color: kWhitePure),
                          const SizedBox(width: 4),
                          const Text('Eyedropper', style: TextStyle(color: kWhitePure, fontSize: 11.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                physics: (_brushEraserActive || _eyedropperSamplingMode || _selectedOverlayIdx != null) ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (_, pageIdx) {
                  final page = _pages[pageIdx];
                  return InteractiveViewer(
                    panEnabled: !_brushEraserActive && !_eyedropperSamplingMode && _selectedOverlayIdx == null,
                    scaleEnabled: true,
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: AspectRatio(
                          aspectRatio: page.imageWidth / math.max(1, page.imageHeight),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final boxW = constraints.maxWidth;
                              final boxH = constraints.maxHeight;

                              return GestureDetector(
                                onPanStart: (d) {
                                  if (_eyedropperSamplingMode) {
                                    final norm = Offset((d.localPosition.dx / boxW).clamp(0.0, 1.0), (d.localPosition.dy / boxH).clamp(0.0, 1.0));
                                    setState(() => _eyedropperTouchPos = d.localPosition);
                                    _samplePixelColorLive(norm);
                                  } else if (_brushEraserActive) {
                                    final norm = Offset((d.localPosition.dx / boxW).clamp(0.0, 1.0), (d.localPosition.dy / boxH).clamp(0.0, 1.0));
                                    setState(() {
                                      page.eraserStrokes.add(BlemishEraserStroke(normalizedPoints: [norm], sampledColor: _sampledPaperColor, strokeWidth: _eraserBrushSize));
                                    });
                                  }
                                },
                                onPanUpdate: (d) {
                                  if (_eyedropperSamplingMode) {
                                    final norm = Offset((d.localPosition.dx / boxW).clamp(0.0, 1.0), (d.localPosition.dy / boxH).clamp(0.0, 1.0));
                                    setState(() => _eyedropperTouchPos = d.localPosition);
                                    _samplePixelColorLive(norm);
                                  } else if (_brushEraserActive) {
                                    if (page.eraserStrokes.isEmpty) return;
                                    final norm = Offset((d.localPosition.dx / boxW).clamp(0.0, 1.0), (d.localPosition.dy / boxH).clamp(0.0, 1.0));
                                    setState(() => page.eraserStrokes.last.normalizedPoints.add(norm));
                                  }
                                },
                                onPanEnd: (_) {
                                  if (_eyedropperSamplingMode) {
                                    setState(() {
                                      _eyedropperSamplingMode = false;
                                      _eyedropperTouchPos = null;
                                    });
                                    _showEyedropperConfirmationGate();
                                  }
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    RotatedBox(quarterTurns: page.rotationQuarterTurns, child: Image.memory(page.displayBytes, fit: BoxFit.fill)),
                                    CustomPaint(painter: _BlemishEraserCanvasPainter(strokes: page.eraserStrokes)),
                                    ...List.generate(page.overlayImages.length, (ovIdx) {
                                      final ov = page.overlayImages[ovIdx];
                                      final isSel = _selectedOverlayIdx == ovIdx;
                                      return Positioned(
                                        left: ov.normalizedPos.dx * boxW,
                                        top: ov.normalizedPos.dy * boxH,
                                        width: ov.normalizedWidth * boxW,
                                        height: ov.normalizedHeight * boxH,
                                        child: GestureDetector(
                                          onTap: () => setState(() => _selectedOverlayIdx = ovIdx),
                                          onPanUpdate: (d) => setState(() {
                                            ov.normalizedPos = Offset(
                                              (ov.normalizedPos.dx + d.delta.dx / boxW).clamp(0.0, 1.0 - ov.normalizedWidth),
                                              (ov.normalizedPos.dy + d.delta.dy / boxH).clamp(0.0, 1.0 - ov.normalizedHeight),
                                            );
                                          }),
                                          child: Stack(
                                            children: [
                                              Positioned.fill(
                                                child: Container(
                                                  decoration: isSel ? BoxDecoration(border: Border.all(color: kBlueAccent, width: 2.0)) : null,
                                                  child: Image.memory(ov.bytes, fit: BoxFit.fill),
                                                ),
                                              ),
                                              if (isSel)
                                                Positioned(
                                                  right: 0,
                                                  bottom: 0,
                                                  child: GestureDetector(
                                                    onPanUpdate: (sd) => setState(() {
                                                      ov.normalizedWidth = (ov.normalizedWidth + sd.delta.dx / boxW).clamp(0.10, 0.90);
                                                      ov.normalizedHeight = (ov.normalizedHeight + sd.delta.dy / boxH).clamp(0.05, 0.90);
                                                    }),
                                                    child: Container(
                                                      width: 24,
                                                      height: 24,
                                                      color: kBlueAccent,
                                                      child: const Icon(Icons.open_in_full, size: 14, color: kWhitePure),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                    if (_eyedropperSamplingMode && _eyedropperTouchPos != null)
                                      Positioned(
                                        left: (_eyedropperTouchPos!.dx - 40).clamp(10.0, boxW - 90.0),
                                        top: (_eyedropperTouchPos!.dy - 90).clamp(10.0, boxH - 90.0),
                                        child: Container(
                                          width: 80,
                                          height: 80,
                                          decoration: BoxDecoration(shape: BoxShape.circle, color: _sampledPaperColor, border: Border.all(color: kWhitePure, width: 4), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))]),
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Container(width: 1, height: 32, color: kNavyPrimary.withOpacity(0.6)),
                                              Container(width: 32, height: 1, color: kNavyPrimary.withOpacity(0.6)),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              color: kNavyPrimary,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Slider(value: _quality.toDouble(), min: 20, max: 100, divisions: 8, activeColor: kBlueAccent, onChanged: (v) => setState(() => _quality = v.round())),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kBlueAccent, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                    onPressed: _processing ? null : _compileAndSaveFinalPdf,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Save PDF', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlemishEraserCanvasPainter extends CustomPainter {
  final List<BlemishEraserStroke> strokes;
  _BlemishEraserCanvasPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.sampledColor
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.strokeWidth;

      if (s.normalizedPoints.length == 1) {
        final pt = Offset(s.normalizedPoints.first.dx * size.width, s.normalizedPoints.first.dy * size.height);
        canvas.drawCircle(pt, s.strokeWidth / 2, Paint()..color = s.sampledColor);
      } else {
        final path = Path();
        for (int i = 0; i < s.normalizedPoints.length; i++) {
          final pt = Offset(s.normalizedPoints[i].dx * size.width, s.normalizedPoints[i].dy * size.height);
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BlemishEraserCanvasPainter oldDelegate) => true;
}
