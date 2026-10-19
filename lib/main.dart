import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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
  runApp(const ANScanExecutiveApp());
}

// =============================================================================
// 1. THEME, BRANDING & CLASSICAL LOGO EMBLEM WIDGET
// =============================================================================

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kNavySecondary = Color(0xFF1E293B);
const Color kGoldAccent = Color(0xFFD4AF37);
const Color kBronzeAccent = Color(0xFF8C7355);
const Color kIvoryParchment = Color(0xFFF5F2EB);
const Color kSurfaceBg = Color(0xFFF8FAFC);

class ANScanExecutiveApp extends StatelessWidget {
  const ANScanExecutiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AN Scan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kSurfaceBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kNavyPrimary,
          primary: kNavyPrimary,
          secondary: kGoldAccent,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kNavyPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 0.8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
        ),
      ),
      home: const ExecutiveMasterShell(),
    );
  }
}

/// Renders the finalized Classical Ivory & Bronze/Gold "AN SCAN" Crest
/// Uses `assets/logo.png` if bundled, with a high-precision CustomPainter fallback.
class ClassicalANLogoBadge extends StatelessWidget {
  final double size;
  const ClassicalANLogoBadge({super.key, this.size = 54});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kIvoryParchment,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: kGoldAccent, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/logo.png',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => CustomPaint(
          size: Size(size, size),
          painter: _ClassicalCrestPainter(),
        ),
      ),
    );
  }
}

class _ClassicalCrestPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    // Ivory Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = kIvoryParchment,
    );

    // Double Filigree Outer & Inner Rings
    final ringPaint = Paint()
      ..color = const Color(0xFF3A322A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.025;
    canvas.drawCircle(center, w * 0.42, ringPaint);

    final innerRingPaint = Paint()
      ..color = kBronzeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012;
    canvas.drawCircle(center, w * 0.38, innerRingPaint);

    // Classical Serif "AN" + "SCAN" Text
    final tpAN = TextPainter(
      text: TextSpan(
        text: 'AN',
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: w * 0.36,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF3A322A),
          letterSpacing: -1.5,
          height: 1.0,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tpAN.paint(canvas, Offset((w - tpAN.width) / 2, h * 0.18));

    // Magnifying Lens Accent in Center
    final lensCenter = Offset(w * 0.51, h * 0.47);
    canvas.drawCircle(
      lensCenter,
      w * 0.08,
      Paint()..color = kIvoryParchment,
    );
    canvas.drawCircle(
      lensCenter,
      w * 0.08,
      Paint()
        ..color = const Color(0xFF3A322A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.03,
    );
    canvas.drawLine(
      Offset(lensCenter.dx + w * 0.05, lensCenter.dy + w * 0.05),
      Offset(lensCenter.dx + w * 0.13, lensCenter.dy + w * 0.13),
      Paint()
        ..color = const Color(0xFF3A322A)
        ..strokeWidth = w * 0.04
        ..strokeCap = StrokeCap.round,
    );

    final tpScan = TextPainter(
      text: TextSpan(
        text: 'SCAN',
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: w * 0.14,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF3A322A),
          letterSpacing: 2.0,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tpScan.paint(canvas, Offset((w - tpScan.width) / 2, h * 0.64));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =============================================================================
// 2. DATA MODELS FOR VAULT, PAGES, OCR & ANNOTATIONS
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

class OcrWordBox {
  final String text;
  final Rect boundingBox; // In original image pixel coordinates

  OcrWordBox({required this.text, required this.boundingBox});
}

class PageAnnotationItem {
  final String type; // 'stamp', 'watermark', 'whiteout', 'signature'
  final String text;
  final Offset normalizedPos; // 0.0 - 1.0 relative to page
  final Color color;
  final Uint8List? signaturePng;

  PageAnnotationItem({
    required this.type,
    this.text = '',
    this.normalizedPos = const Offset(0.5, 0.5),
    this.color = Colors.red,
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

  EditableDocumentPage({
    required this.originalBytes,
    required this.displayBytes,
    this.imageWidth = 1000,
    this.imageHeight = 1400,
    this.rotationQuarterTurns = 0,
    this.activeFilter = ScanColorFilter.original,
    List<OcrWordBox>? ocrWords,
    List<PageAnnotationItem>? annotations,
  })  : ocrWords = ocrWords ?? [],
        annotations = annotations ?? [];
}

// =============================================================================
// 3. UNIVERSAL 8-WAY FORMAT CONVERSION ENGINE
// =============================================================================

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

class UniversalFormatConverterEngine {
  /// Extracts text from a `.docx` OpenXML archive
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
          return lines.isEmpty ? ['(Empty Word Document)'] : lines;
        }
      }
    } catch (_) {}
    // Fallback plain UTF8 decode
    final raw = utf8.decode(docxBytes, allowMalformed: true);
    return raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
  }

  /// Builds a genuine OpenXML `.docx` file from paragraphs or table rows
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

    // Title Header
    sb.write('<w:p><w:r><w:rPr><w:b/><w:sz w:val="32"/></w:rPr><w:t>${esc.convert(title)}</w:t></w:r></w:p>');

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

  /// Extracts rows from `.xlsx` or `.csv`
  static List<List<String>> extractRowsFromExcelOrCsv(Uint8List bytes, String ext) {
    if (ext.toUpperCase() == 'CSV') {
      final content = utf8.decode(bytes, allowMalformed: true);
      return content
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => l.split(',').map((c) => c.trim()).toList())
          .toList();
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
      return rows.isEmpty ? [['Empty Sheet']] : rows;
    } catch (_) {
      return [['Unable to parse binary spreadsheet']];
    }
  }

  /// Builds `.xlsx` bytes from structured rows
  static Uint8List buildExcelBytes(List<List<String>> rows, {String sheetName = 'AN_Scan_Sheet'}) {
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
    final encoded = excel.encode();
    return Uint8List.fromList(encoded ?? []);
  }

  /// Runs OCR over all pages of a PDF and returns structured lines + table columns
  static Future<List<String>> extractOcrLinesFromPdf(Uint8List pdfBytes, {bool hindi = false}) async {
    final recognizer = TextRecognizer(
      script: hindi ? TextRecognitionScript.devanagari : TextRecognitionScript.latin,
    );
    final List<String> allLines = [];
    final tmpDir = await getTemporaryDirectory();
    int pageNum = 1;

    try {
      await for (final page in Printing.raster(pdfBytes, dpi: 170)) {
        final png = await page.toPng();
        final tmpFile = File(p.join(tmpDir.path, 'ocr_page_$pageNum.png'));
        await tmpFile.writeAsBytes(png);
        final recognized = await recognizer.processImage(InputImage.fromFilePath(tmpFile.path));
        allLines.add('--- Page $pageNum ---');
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
    return allLines;
  }
}

// =============================================================================
// 4. EXECUTIVE MASTER SHELL (HOME STUDIO, VAULT, ACCOUNTS & INTENT HANDLER)
// =============================================================================

class ExecutiveMasterShell extends StatefulWidget {
  const ExecutiveMasterShell({super.key});

  @override
  State<ExecutiveMasterShell> createState() => _ExecutiveMasterShellState();
}

class _ExecutiveMasterShellState extends State<ExecutiveMasterShell> {
  static const MethodChannel _intentChannel = MethodChannel('in.adeshnarang.an_scan/intent');

  int _tabIndex = 0;
  List<VaultFile> _vaultFiles = [];
  Set<String> _lockedFileNames = {};
  String _searchQuery = '';
  String _selectedCategory = 'ALL';

  List<String> _accounts = ['Adesh Narang (Admin)', 'Head Office Desk', 'Personal Vault'];
  String _currentAccount = 'Adesh Narang (Admin)';
  String? _masterPin;
  bool _isVaultUnlocked = false;
  int _defaultCompression = 80;
  bool _preferHindiOcr = false;

  @override
  void initState() {
    super.initState();
    _initWorkspace();
    _setupNativeIntentInterceptor();
  }

  void _setupNativeIntentInterceptor() {
    // Listen for live files opened while app is in memory
    _intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onIncomingFile' && call.arguments is String) {
        final incomingPath = call.arguments as String;
        await _ingestAndOpenExternalIntentFile(incomingPath);
      }
    });

    // Check if app was cold-launched via "Open With AN Scan" from Gmail / WhatsApp / Files
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opened & Saved "$fileName" into Vault'),
        backgroundColor: kNavyPrimary,
      ),
    );

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
      _accounts = prefs.getStringList('user_accounts') ??
          ['Adesh Narang (Admin)', 'Head Office Desk', 'Personal Vault'];
      _currentAccount = prefs.getString('active_account') ?? _accounts.first;
      _masterPin = prefs.getString('master_pin');
      _defaultCompression = prefs.getInt('default_compression') ?? 80;
      _preferHindiOcr = prefs.getBool('prefer_hindi_ocr') ?? false;
      _lockedFileNames = (prefs.getStringList('locked_files') ?? []).toSet();
      _isVaultUnlocked = (_masterPin == null || _masterPin!.isEmpty);
    });
    await _reloadVault();
  }

  Future<Directory> _getAccountVaultDir() async {
    final base = await getApplicationDocumentsDirectory();
    final safeFolder = _currentAccount.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final dir = Directory(p.join(base.path, 'AN_Scan_Vault', safeFolder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
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
        if (['PDF', 'DOCX', 'XLSX', 'CSV', 'TXT', 'PNG', 'JPG', 'JPEG'].contains(ext)) {
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
    if (mounted) {
      setState(() => _vaultFiles = loaded);
    }
  }

  Future<void> _importExternalFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'xlsx', 'csv', 'txt', 'png', 'jpg', 'jpeg'],
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${result.files.length} file(s) into AN Scan Vault!'),
            action: SnackBarAction(
              label: 'OPEN',
              textColor: kGoldAccent,
              onPressed: () => _openVaultFile(lastImported!),
            ),
          ),
        );
      }
    }
  }

  Future<void> _startScannerWorkflow({required bool fromGallery}) async {
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

    // Step 1: If single image captured, open 4-Corner Perspective Crop Studio immediately
    final List<EditableDocumentPage> initialPages = [];
    for (int i = 0; i < rawPaths.length; i++) {
      final rawBytes = await File(rawPaths[i]).readAsBytes();
      Uint8List processedBytes = rawBytes;

      if (rawPaths.length == 1 && mounted) {
        final cropped = await Navigator.push<Uint8List>(
          context,
          MaterialPageRoute(
            builder: (_) => FourCornerPerspectiveCropScreen(
              imageBytes: rawBytes,
              pageTitle: '4-Corner Perspective Crop',
            ),
          ),
        );
        if (cropped == null) return; // User cancelled scan
        processedBytes = cropped;
      }

      final decoded = img.decodeImage(processedBytes);
      initialPages.add(
        EditableDocumentPage(
          originalBytes: processedBytes,
          displayBytes: processedBytes,
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
          initialTitle: 'AN_Scan_${DateFormat('ddMMM_HHmm').format(DateTime.now())}',
          defaultQuality: _defaultCompression,
          preferHindiOcr: _preferHindiOcr,
          onSaveDocument: (pdfBytes, finalFileName) async {
            final dir = await _getAccountVaultDir();
            final cleanName = finalFileName.toLowerCase().endsWith('.pdf')
                ? finalFileName
                : '$finalFileName.pdf';
            final outFile = File(p.join(dir.path, cleanName));
            await outFile.writeAsBytes(pdfBytes);
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
      // Show loading dialog while rasterizing PDF pages into the Full Acrobat Studio
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 18),
              Expanded(child: Text('Opening PDF in AN Scan Studio...')),
            ],
          ),
        ),
      );

      try {
        final pdfBytes = await File(file.path).readAsBytes();
        final List<EditableDocumentPage> pages = [];
        await for (final rasterPage in Printing.raster(pdfBytes, dpi: 165)) {
          final png = await rasterPage.toPng();
          pages.add(
            EditableDocumentPage(
              originalBytes: png,
              displayBytes: png,
              imageWidth: rasterPage.width,
              imageHeight: rasterPage.height,
            ),
          );
        }
        if (mounted) Navigator.pop(context); // Dismiss loader

        if (pages.isEmpty) {
          await OpenFilex.open(file.path);
          return;
        }

        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AcrobatDocumentStudioScreen(
              initialPages: pages,
              initialTitle: file.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
              defaultQuality: _defaultCompression,
              preferHindiOcr: _preferHindiOcr,
              existingFilePath: file.path,
              onSaveDocument: (updatedBytes, finalName) async {
                final dir = await _getAccountVaultDir();
                final cleanName = finalName.toLowerCase().endsWith('.pdf') ? finalName : '$finalName.pdf';
                await File(p.join(dir.path, cleanName)).writeAsBytes(updatedBytes);
                await _reloadVault();
              },
            ),
          ),
        );
      } catch (e) {
        if (mounted) Navigator.pop(context);
        await OpenFilex.open(file.path);
      }
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
            preferHindiOcr: _preferHindiOcr,
            onSaveDocument: (pdfBytes, finalName) async {
              final dir = await _getAccountVaultDir();
              final cleanName = finalName.toLowerCase().endsWith('.pdf') ? finalName : '$finalName.pdf';
              await File(p.join(dir.path, cleanName)).writeAsBytes(pdfBytes);
              await _reloadVault();
            },
          ),
        ),
      );
    } else {
      // Open Word/Excel/CSV in in-app preview or external handler
      await _showOfficeFilePreviewSheet(file);
    }
  }

  Future<void> _showOfficeFilePreviewSheet(VaultFile file) async {
    final bytes = await File(file.path).readAsBytes();
    List<String> previewLines = [];
    if (file.ext == 'DOCX') {
      previewLines = await UniversalFormatConverterEngine.extractLinesFromDocx(bytes);
    } else if (file.ext == 'XLSX' || file.ext == 'CSV') {
      final rows = UniversalFormatConverterEngine.extractRowsFromExcelOrCsv(bytes, file.ext);
      previewLines = rows.map((r) => r.join('  |  ')).toList();
    } else {
      previewLines = utf8.decode(bytes, allowMalformed: true).split('\n');
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    file.name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                    maxLines: 1,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    OpenFilex.open(file.path);
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('External App'),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kSurfaceBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: SelectableText(
                  previewLines.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
          decoration: const InputDecoration(
            labelText: 'Enter 4-Digit PIN',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim() == _masterPin),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  // ===========================================================================
  // UNIVERSAL 8-WAY FORMAT CONVERTER HUB SHEET
  // ===========================================================================
  void _openUniversalConverterHub() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.84,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Universal Format Converter Hub',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: kNavyPrimary),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Convert any document across PDF, Word, Excel & Images',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.38,
                children: [
                  _buildConverterCard(
                    ctx,
                    title: 'PDF → Image',
                    sub: 'Export PDF pages to HD JPG/PNG',
                    icon: Icons.collections_bookmark_outlined,
                    badgeColor: const Color(0xFFDC2626),
                    direction: ConversionDirection.pdfToImage,
                  ),
                  _buildConverterCard(
                    ctx,
                    title: 'Image → PDF',
                    sub: 'Compile JPG/PNG photos into PDF',
                    icon: Icons.picture_as_pdf_outlined,
                    badgeColor: const Color(0xFFEA580C),
                    direction: ConversionDirection.imageToPdf,
                  ),
                  _buildConverterCard(
                    ctx,
                    title: 'PDF → Word',
                    sub: 'Convert PDF into editable .DOCX',
                    icon: Icons.description_outlined,
                    badgeColor: const Color(0xFF1D4ED8),
                    direction: ConversionDirection.pdfToWord,
                  ),
                  _buildConverterCard(
                    ctx,
                    title: 'Word → PDF',
                    sub: 'Convert .DOCX into printable PDF',
                    icon: Icons.article_outlined,
                    badgeColor: const Color(0xFF2563EB),
                    direction: ConversionDirection.wordToPdf,
                  ),
                  _buildConverterCard(
                    ctx,
                    title: 'PDF → Excel',
                    sub: 'Extract PDF tables into .XLSX',
                    icon: Icons.grid_on_rounded,
                    badgeColor: const Color(0xFF15803D),
                    direction: ConversionDirection.pdfToExcel,
                  ),
                  _buildConverterCard(
                    ctx,
                    title: 'Excel → PDF',
                    sub: 'Turn .XLSX/.CSV sheets into PDF',
                    icon: Icons.table_chart_outlined,
                    badgeColor: const Color(0xFF0D9488),
                    direction: ConversionDirection.excelToPdf,
                  ),
                  _buildConverterCard(
                    ctx,
                    title: 'Word → Excel',
                    sub: 'Convert .DOCX lines/tables to .XLSX',
                    icon: Icons.swap_horiz_rounded,
                    badgeColor: const Color(0xFF7C3AED),
                    direction: ConversionDirection.wordToExcel,
                  ),
                  _buildConverterCard(
                    ctx,
                    title: 'Excel → Word',
                    sub: 'Format .XLSX data into .DOCX table',
                    icon: Icons.transform_rounded,
                    badgeColor: const Color(0xFF9333EA),
                    direction: ConversionDirection.excelToWord,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConverterCard(
    BuildContext sheetContext, {
    required String title,
    required String sub,
    required IconData icon,
    required Color badgeColor,
    required ConversionDirection direction,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(sheetContext);
        _executeConversionWorkflow(direction);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurfaceBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: badgeColor.withOpacity(0.28), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: badgeColor, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: kNavyPrimary),
              maxLines: 1,
            ),
            const SizedBox(height: 3),
            Text(
              sub,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeConversionWorkflow(ConversionDirection dir) async {
    if (dir == ConversionDirection.imageToPdf) {
      await _startScannerWorkflow(fromGallery: true);
      return;
    }

    List<String> allowedExts = ['pdf'];
    if (dir == ConversionDirection.wordToPdf || dir == ConversionDirection.wordToExcel) {
      allowedExts = ['docx', 'txt'];
    } else if (dir == ConversionDirection.excelToPdf || dir == ConversionDirection.excelToWord) {
      allowedExts = ['xlsx', 'csv'];
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExts,
    );
    if (picked == null || picked.files.single.path == null) return;

    final srcPath = picked.files.single.path!;
    final baseName = p.basenameWithoutExtension(srcPath);
    final ext = p.extension(srcPath).replaceAll('.', '').toUpperCase();
    final rawBytes = await File(srcPath).readAsBytes();
    final vaultDir = await _getAccountVaultDir();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Processing format conversion...')),
          ],
        ),
      ),
    );

    try {
      String outputMessage = 'Conversion completed!';
      switch (dir) {
        case ConversionDirection.pdfToImage:
          int pNum = 1;
          await for (final page in Printing.raster(rawBytes, dpi: 200)) {
            final png = await page.toPng();
            await File(p.join(vaultDir.path, '${baseName}_Page_$pNum.png')).writeAsBytes(png);
            pNum++;
          }
          outputMessage = 'Extracted ${pNum - 1} page image(s) to Vault!';
          break;

        case ConversionDirection.pdfToWord:
          final lines = await UniversalFormatConverterEngine.extractOcrLinesFromPdf(
            rawBytes,
            hindi: _preferHindiOcr,
          );
          final docx = UniversalFormatConverterEngine.buildDocxBytes(
            title: baseName,
            paragraphs: lines,
          );
          await File(p.join(vaultDir.path, '${baseName}_Converted.docx')).writeAsBytes(docx);
          outputMessage = 'Converted PDF to editable Word (.docx)!';
          break;

        case ConversionDirection.wordToPdf:
          final lines = await UniversalFormatConverterEngine.extractLinesFromDocx(rawBytes);
          final pdf = pw.Document();
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(32),
              build: (_) => [
                pw.Header(
                  level: 0,
                  child: pw.Text(baseName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                ),
                ...lines.map(
                  (l) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text(l, style: const pw.TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
          );
          await File(p.join(vaultDir.path, '${baseName}_WordToPdf.pdf')).writeAsBytes(await pdf.save());
          outputMessage = 'Converted Word document to PDF!';
          break;

        case ConversionDirection.pdfToExcel:
          final lines = await UniversalFormatConverterEngine.extractOcrLinesFromPdf(
            rawBytes,
            hindi: _preferHindiOcr,
          );
          final List<List<String>> rows = lines
              .map((l) => l.split(RegExp(r'\s{2,}|\t')).map((e) => e.trim()).toList())
              .toList();
          final xlsxBytes = UniversalFormatConverterEngine.buildExcelBytes(rows, sheetName: 'PDF_Extract');
          await File(p.join(vaultDir.path, '${baseName}_Table.xlsx')).writeAsBytes(xlsxBytes);
          outputMessage = 'Converted PDF to Excel (.xlsx)!';
          break;

        case ConversionDirection.excelToPdf:
          final rows = UniversalFormatConverterEngine.extractRowsFromExcelOrCsv(rawBytes, ext);
          final pdf = pw.Document();
          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(24),
              build: (_) => [
                pw.Header(
                  level: 0,
                  child: pw.Text('Spreadsheet Report: $baseName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ),
                pw.TableHelper.fromTextArray(
                  data: rows.take(250).toList(),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headerStyle: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          );
          await File(p.join(vaultDir.path, '${baseName}_Sheet.pdf')).writeAsBytes(await pdf.save());
          outputMessage = 'Converted Excel spreadsheet to PDF!';
          break;

        case ConversionDirection.wordToExcel:
          final lines = await UniversalFormatConverterEngine.extractLinesFromDocx(rawBytes);
          final rows = lines
              .map((l) => l.split(RegExp(r'\s{2,}|\t|,')).map((c) => c.trim()).toList())
              .toList();
          final xlsxBytes = UniversalFormatConverterEngine.buildExcelBytes(rows, sheetName: 'From_Word');
          await File(p.join(vaultDir.path, '${baseName}_FromWord.xlsx')).writeAsBytes(xlsxBytes);
          outputMessage = 'Converted Word document to Excel (.xlsx)!';
          break;

        case ConversionDirection.excelToWord:
          final rows = UniversalFormatConverterEngine.extractRowsFromExcelOrCsv(rawBytes, ext);
          final docxBytes = UniversalFormatConverterEngine.buildDocxBytes(
            title: 'Spreadsheet Export: $baseName',
            paragraphs: ['Generated by AN Scan Universal Converter'],
            tableData: rows,
          );
          await File(p.join(vaultDir.path, '${baseName}_FromExcel.docx')).writeAsBytes(docxBytes);
          outputMessage = 'Converted Excel spreadsheet to Word (.docx)!';
          break;

        case ConversionDirection.imageToPdf:
          break;
      }

      await _reloadVault();
      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(outputMessage), backgroundColor: const Color(0xFF15803D)),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Conversion error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ===========================================================================
  // PDF MERGER DIALOG
  // ===========================================================================
  Future<void> _openPdfMergerDialog() async {
    final pdfs = _vaultFiles.where((f) => f.ext == 'PDF').toList();
    if (pdfs.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import or scan at least 2 PDF files in Vault to merge.')),
      );
      return;
    }

    final List<String> selectedPaths = [];
    final nameCtrl = TextEditingController(text: 'Merged_${DateFormat('ddMMM_HHmm').format(DateTime.now())}');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: const Text('Merge Multiple PDFs', style: TextStyle(fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Output Merged PDF Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: pdfs.length,
                    itemBuilder: (_, i) {
                      final isChecked = selectedPaths.contains(pdfs[i].path);
                      return CheckboxListTile(
                        value: isChecked,
                        title: Text(pdfs[i].name, maxLines: 1, style: const TextStyle(fontSize: 13.5)),
                        subtitle: Text(_formatBytes(pdfs[i].sizeBytes), style: const TextStyle(fontSize: 11)),
                        onChanged: (v) {
                          setModal(() {
                            if (v == true) {
                              selectedPaths.add(pdfs[i].path);
                            } else {
                              selectedPaths.remove(pdfs[i].path);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: selectedPaths.length < 2
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final mergedDoc = pw.Document();
                      for (final path in selectedPaths) {
                        final raw = await File(path).readAsBytes();
                        await for (final page in Printing.raster(raw, dpi: 160)) {
                          final png = await page.toPng();
                          mergedDoc.addPage(
                            pw.Page(
                              pageFormat: PdfPageFormat.a4,
                              margin: pw.EdgeInsets.zero,
                              build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain)),
                            ),
                          );
                        }
                      }
                      final dir = await _getAccountVaultDir();
                      final clean = nameCtrl.text.trim().endsWith('.pdf')
                          ? nameCtrl.text.trim()
                          : '${nameCtrl.text.trim()}.pdf';
                      await File(p.join(dir.path, clean)).writeAsBytes(await mergedDoc.save());
                      await _reloadVault();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Merged ${selectedPaths.length} PDFs into $clean!')),
                        );
                      }
                    },
              icon: const Icon(Icons.call_merge),
              label: Text('Merge (${selectedPaths.length})'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  // ===========================================================================
  // MAIN SHELL BUILD (WITH NON-OVERLAPPING BOTTOM BAR)
  // ===========================================================================
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
                    const ClassicalANLogoBadge(size: 76),
                    const SizedBox(height: 16),
                    const Text(
                      'AN SCAN VAULT LOCKED',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _currentAccount,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        labelText: '4-Digit Master PIN',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          if (pinCtrl.text.trim() == _masterPin) {
                            setState(() => _isVaultUnlocked = true);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Incorrect Master PIN')),
                            );
                          }
                        },
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Unlock Executive Workspace'),
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

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Row(
          children: [
            const ClassicalANLogoBadge(size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A N   S C A N',
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.2,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '$_currentAccount • adeshnarang.in',
                    style: const TextStyle(fontSize: 11, color: kGoldAccent, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Quick Camera Scan',
            icon: const Icon(Icons.camera_alt_outlined, color: kGoldAccent),
            onPressed: () => _startScannerWorkflow(fromGallery: false),
          ),
          IconButton(
            tooltip: 'Import External PDF / Office File',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _importExternalFilePicker,
          ),
          IconButton(
            tooltip: 'Refresh Vault',
            icon: const Icon(Icons.sync),
            onPressed: _reloadVault,
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildExecutiveStudioDashboard(),
          _buildVaultDirectoryTab(),
          _buildAccountsAndSecurityTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_customize_outlined),
            selectedIcon: Icon(Icons.dashboard_customize),
            label: 'Studio',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_special_outlined),
            selectedIcon: Icon(Icons.folder_special),
            label: 'File Vault',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_user_outlined),
            selectedIcon: Icon(Icons.verified_user),
            label: 'Accounts',
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: CLEAN EXECUTIVE STUDIO DASHBOARD (ZERO OVERLAP)
  // ===========================================================================
  Widget _buildExecutiveStudioDashboard() {
    return ListView(
      // Extra bottom padding guarantees nothing is ever hidden or blocked while scrolling
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
      children: [
        // Hero Executive Banner with Docked Quick Scan Action (Replaces overlapping FAB!)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [kNavyPrimary, kNavySecondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kGoldAccent.withOpacity(0.45), width: 1.2),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const ClassicalANLogoBadge(size: 58),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AN Scan Document Studio',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16.5,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_vaultFiles.length} Vault Docs • Selectable OCR & 8-Way Converter',
                          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                        ),
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
                        backgroundColor: kGoldAccent,
                        foregroundColor: kNavyPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _startScannerWorkflow(fromGallery: false),
                      icon: const Icon(Icons.camera_enhance_rounded, size: 20),
                      label: const Text(
                        'Capture & Perspective Scan',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.12),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _importExternalFilePicker,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Import'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'CORE SCANNER, ACROBAT & CONVERTER SUITE',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.42,
          children: [
            _buildStudioToolTile(
              icon: Icons.Autorenew_rounded,
              fallbackIcon: Icons.hub_outlined,
              title: 'Format Converter Hub',
              sub: 'All 8 Formats: PDF ⇄ Word ⇄ Excel ⇄ Img',
              accent: const Color(0xFFB45309),
              onTap: _openUniversalConverterHub,
            ),
            _buildStudioToolTile(
              icon: Icons.crop_free_rounded,
              fallbackIcon: Icons.crop_free_rounded,
              title: '4-Corner Camera Scan',
              sub: 'Perspective Warp & Auto Filters',
              accent: kNavyPrimary,
              onTap: () => _startScannerWorkflow(fromGallery: false),
            ),
            _buildStudioToolTile(
              icon: Icons.collections_outlined,
              fallbackIcon: Icons.collections_outlined,
              title: 'Gallery Batch to PDF',
              sub: 'Multi-Photo Import & Compress',
              accent: const Color(0xFF1D4ED8),
              onTap: () => _startScannerWorkflow(fromGallery: true),
            ),
            _buildStudioToolTile(
              icon: Icons.document_scanner_outlined,
              fallbackIcon: Icons.document_scanner_outlined,
              title: 'In-Place Visual OCR',
              sub: 'Select Text Directly on Picture',
              accent: const Color(0xFF15803D),
              onTap: () async {
                final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                if (picked != null && mounted) {
                  final bytes = await File(picked.path).readAsBytes();
                  final decoded = img.decodeImage(bytes);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InPlaceSelectableOcrScreen(
                        imageBytes: bytes,
                        imageWidth: decoded?.width ?? 1000,
                        imageHeight: decoded?.height ?? 1400,
                        initialHindi: _preferHindiOcr,
                      ),
                    ),
                  );
                }
              },
            ),
            _buildStudioToolTile(
              icon: Icons.edit_document,
              fallbackIcon: Icons.edit_document,
              title: 'Edit / Sign / Stamp PDF',
              sub: 'Open External PDF in Studio',
              accent: const Color(0xFFDC2626),
              onTap: _importExternalFilePicker,
            ),
            _buildStudioToolTile(
              icon: Icons.call_merge_rounded,
              fallbackIcon: Icons.call_merge_rounded,
              title: 'Merge Multiple PDFs',
              sub: 'Combine Vault PDFs into One',
              accent: const Color(0xFF7C3AED),
              onTap: _openPdfMergerDialog,
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECENT WORKSPACE DOCUMENTS',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                color: Color(0xFF475569),
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _tabIndex = 1),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Open Vault'),
            ),
          ],
        ),
        if (_vaultFiles.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Icon(Icons.folder_copy_outlined, size: 42, color: Color(0xFF94A3B8)),
                  const SizedBox(height: 10),
                  const Text(
                    'Your AN Scan Vault is Ready',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Scan a document, open a PDF from Gmail, or use the Format Converter Hub.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          )
        else
          ..._vaultFiles.take(6).map(_buildVaultFileCard),
      ],
    );
  }

  Widget _buildStudioToolTile({
    required IconData icon,
    required IconData fallbackIcon,
    required String title,
    required String sub,
    required Color accent,
    required VoidCallback onTap,
  }) {
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
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(fallbackIcon, color: accent, size: 24),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: kNavyPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: FILE VAULT DIRECTORY
  // ===========================================================================
  Widget _buildVaultDirectoryTab() {
    final filtered = _vaultFiles.where((f) {
      final matchesSearch = f.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCat = _selectedCategory == 'ALL' ||
          (_selectedCategory == 'PDF' && f.ext == 'PDF') ||
          (_selectedCategory == 'WORD' && (f.ext == 'DOCX' || f.ext == 'TXT')) ||
          (_selectedCategory == 'EXCEL' && (f.ext == 'XLSX' || f.ext == 'CSV')) ||
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
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
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
                child: ChoiceChip(
                  label: Text(cat),
                  selected: active,
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matching files in Vault.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _buildVaultFileCard(filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildVaultFileCard(VaultFile file) {
    Color badge = const Color(0xFFDC2626);
    if (file.ext == 'XLSX' || file.ext == 'CSV') badge = const Color(0xFF15803D);
    if (file.ext == 'DOCX') badge = const Color(0xFF1D4ED8);
    if (['PNG', 'JPG', 'JPEG'].contains(file.ext)) badge = const Color(0xFFB45309);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => _openVaultFile(file),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badge.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            file.ext,
            style: TextStyle(color: badge, fontWeight: FontWeight.w900, fontSize: 10.5),
          ),
        ),
        title: Row(
          children: [
            if (file.isLocked)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.lock, size: 15, color: kGoldAccent),
              ),
            Expanded(
              child: Text(
                file.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${_formatBytes(file.sizeBytes)} • ${DateFormat('dd MMM yyyy, hh:mm a').format(file.modified)}',
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'open') {
              await _openVaultFile(file);
            } else if (action == 'share') {
              await Share.shareXFiles([XFile(file.path)], text: file.name);
            } else if (action == 'lock') {
              final prefs = await SharedPreferences.getInstance();
              setState(() {
                if (_lockedFileNames.contains(file.name)) {
                  _lockedFileNames.remove(file.name);
                } else {
                  _lockedFileNames.add(file.name);
                }
              });
              await prefs.setStringList('locked_files', _lockedFileNames.toList());
              await _reloadVault();
            } else if (action == 'rename') {
              final ctrl = TextEditingController(text: file.name);
              final newName = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Rename Document'),
                  content: TextField(controller: ctrl, decoration: const InputDecoration(border: OutlineInputBorder())),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Rename')),
                  ],
                ),
              );
              if (newName != null && newName.isNotEmpty) {
                final newPath = p.join(p.dirname(file.path), newName);
                await File(file.path).rename(newPath);
                await _reloadVault();
              }
            } else if (action == 'delete') {
              await File(file.path).delete();
              await _reloadVault();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'open', child: Text('Open in Studio')),
            const PopupMenuItem(value: 'share', child: Text('Share / Export')),
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(
              value: 'lock',
              child: Text(file.isLocked ? 'Remove PIN Lock' : 'Protect with PIN'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete Document', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 3: ACCOUNTS, OCR SCRIPT & SECURITY SETTINGS
  // ===========================================================================
  Widget _buildAccountsAndSecurityTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ACTIVE WORKSPACE PROFILE', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
                const SizedBox(height: 10),
                ..._accounts.map(
                  (acc) => RadioListTile<String>(
                    value: acc,
                    groupValue: _currentAccount,
                    title: Text(acc, style: const TextStyle(fontWeight: FontWeight.bold)),
                    onChanged: (val) async {
                      if (val != null) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('active_account', val);
                        setState(() => _currentAccount = val);
                        await _reloadVault();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Default Devanagari (Hindi) + Latin OCR', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Enable bilingual Hindi & English recognition by default'),
                value: _preferHindiOcr,
                onChanged: (v) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('prefer_hindi_ocr', v);
                  setState(() => _preferHindiOcr = v);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.pin_outlined, color: kNavyPrimary),
                title: Text(_masterPin == null || _masterPin!.isEmpty ? 'Set 4-Digit Vault Master PIN' : 'Change / Remove Vault PIN'),
                subtitle: const Text('Protects locked files and app startup'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final ctrl = TextEditingController(text: _masterPin ?? '');
                  final saved = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Configure 4-Digit PIN'),
                      content: TextField(
                        controller: ctrl,
                        maxLength: 4,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Leave empty to disable PIN',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
                      ],
                    ),
                  );
                  if (saved != null) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('master_pin', saved);
                    setState(() => _masterPin = saved.isEmpty ? null : saved);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const ClassicalANLogoBadge(size: 42),
            title: const Text('Engineered by Adesh Narang', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: const Text('Official Executive Portal: https://adeshnarang.in'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse('https://adeshnarang.in')),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// 5. INTERACTIVE 4-CORNER PERSPECTIVE CROPPING & HOMOGRAPHY WARP STUDIO
// =============================================================================

class FourCornerPerspectiveCropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String pageTitle;

  const FourCornerPerspectiveCropScreen({
    super.key,
    required this.imageBytes,
    required this.pageTitle,
  });

  @override
  State<FourCornerPerspectiveCropScreen> createState() => _FourCornerPerspectiveCropScreenState();
}

class _FourCornerPerspectiveCropScreenState extends State<FourCornerPerspectiveCropScreen> {
  // Normalized coordinates (0.0 to 1.0) for Top-Left, Top-Right, Bottom-Right, Bottom-Left
  List<Offset> _corners = [
    const Offset(0.08, 0.08),
    const Offset(0.92, 0.08),
    const Offset(0.92, 0.92),
    const Offset(0.08, 0.92),
  ];

  int? _activeDragIndex;
  Offset? _activeTouchNormalized;
  bool _processingWarp = false;
  ui.Image? _decodedUiImage;

  @override
  void initState() {
    super.initState();
    _loadUiImage();
  }

  Future<void> _loadUiImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() => _decodedUiImage = frame.image);
    }
  }

  /// Performs true Bilinear Perspective Homography Warping using the 4 corner pins
  Future<Uint8List> _performPerspectiveWarp() async {
    final srcImg = img.decodeImage(widget.imageBytes);
    if (srcImg == null) return widget.imageBytes;

    final w = srcImg.width.toDouble();
    final h = srcImg.height.toDouble();

    final p0 = Offset(_corners[0].dx * w, _corners[0].dy * h); // TL
    final p1 = Offset(_corners[1].dx * w, _corners[1].dy * h); // TR
    final p2 = Offset(_corners[2].dx * w, _corners[2].dy * h); // BR
    final p3 = Offset(_corners[3].dx * w, _corners[3].dy * h); // BL

    final topWidth = (p1 - p0).distance;
    final bottomWidth = (p2 - p3).distance;
    final leftHeight = (p3 - p0).distance;
    final rightHeight = (p2 - p1).distance;

    final outW = math.max(200, math.max(topWidth, bottomWidth).round());
    final outH = math.max(200, math.max(leftHeight, rightHeight).round());

    final dstImg = img.Image(width: outW, height: outH);

    for (int y = 0; y < outH; y++) {
      final v = y / (outH - 1);
      for (int x = 0; x < outW; x++) {
        final u = x / (outW - 1);
        final srcX = (1 - u) * (1 - v) * p0.dx +
            u * (1 - v) * p1.dx +
            u * v * p2.dx +
            (1 - u) * v * p3.dx;
        final srcY = (1 - u) * (1 - v) * p0.dy +
            u * (1 - v) * p1.dy +
            u * v * p2.dy +
            (1 - u) * v * p3.dy;

        final sx = srcX.round().clamp(0, srcImg.width - 1);
        final sy = srcY.round().clamp(0, srcImg.height - 1);
        dstImg.setPixel(x, y, srcImg.getPixel(sx, sy));
      }
    }

    return Uint8List.fromList(img.encodeJpg(dstImg, quality: 92));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        title: Text(widget.pageTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          TextButton.icon(
            onPressed: () {
              setState(() {
                _corners = [
                  const Offset(0.02, 0.02),
                  const Offset(0.98, 0.02),
                  const Offset(0.98, 0.98),
                  const Offset(0.02, 0.98),
                ];
              });
            },
            icon: const Icon(Icons.select_all, color: kGoldAccent, size: 18),
            label: const Text('Full Page', style: TextStyle(color: kGoldAccent)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: kNavySecondary,
            child: const Text(
              'Drag any of the 4 corner pins or edge handles to perspective-crop the document.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final boxW = constraints.maxWidth;
                  final boxH = constraints.maxHeight;

                  return GestureDetector(
                    onPanStart: (details) {
                      final local = details.localPosition;
                      final norm = Offset(
                        (local.dx / boxW).clamp(0.0, 1.0),
                        (local.dy / boxH).clamp(0.0, 1.0),
                      );
                      int closestIdx = 0;
                      double minDist = 999;
                      for (int i = 0; i < 4; i++) {
                        final d = ( norm - _corners[i] ).distance;
                        if (d < minDist) {
                          minDist = d;
                          closestIdx = i;
                        }
                      }
                      if (minDist < 0.22) {
                        setState(() {
                          _activeDragIndex = closestIdx;
                          _activeTouchNormalized = norm;
                        });
                      }
                    },
                    onPanUpdate: (details) {
                      if (_activeDragIndex == null) return;
                      final local = details.localPosition;
                      final norm = Offset(
                        (local.dx / boxW).clamp(0.0, 1.0),
                        (local.dy / boxH).clamp(0.0, 1.0),
                      );
                      setState(() {
                        _corners[_activeDragIndex!] = norm;
                        _activeTouchNormalized = norm;
                      });
                    },
                    onPanEnd: (_) {
                      setState(() {
                        _activeDragIndex = null;
                        _activeTouchNormalized = null;
                      });
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(widget.imageBytes, fit: BoxFit.fill),
                        CustomPaint(
                          painter: _PerspectiveCropGridPainter(
                            corners: _corners,
                            activeCorner: _activeDragIndex,
                          ),
                        ),
                        // Precision Magnifier Loupe in Top-Left while dragging
                        if (_activeTouchNormalized != null && _decodedUiImage != null)
                          Positioned(
                            top: 8,
                            left: _activeTouchNormalized!.dx < 0.45 ? null : 8,
                            right: _activeTouchNormalized!.dx < 0.45 ? 8 : null,
                            child: Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: kGoldAccent, width: 3),
                                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: CustomPaint(
                                painter: _MagnifierLoupePainter(
                                  image: _decodedUiImage!,
                                  normalizedCenter: _activeTouchNormalized!,
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
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(context, widget.imageBytes),
                    child: const Text('Skip Crop'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kGoldAccent,
                      foregroundColor: kNavyPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _processingWarp
                        ? null
                        : () async {
                            setState(() => _processingWarp = true);
                            final warped = await _performPerspectiveWarp();
                            if (mounted) Navigator.pop(context, warped);
                          },
                    icon: const Icon(Icons.crop_rotate),
                    label: Text(
                      _processingWarp ? 'Applying Perspective Warp...' : 'Apply Perspective Crop',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PerspectiveCropGridPainter extends CustomPainter {
  final List<Offset> corners;
  final int? activeCorner;

  _PerspectiveCropGridPainter({required this.corners, this.activeCorner});

  @override
  void paint(Canvas canvas, Size size) {
    final pts = corners.map((c) => Offset(c.dx * size.width, c.dy * size.height)).toList();

    final polyPath = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    // Dim outside area
    final fullRect = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final outside = Path.combine(PathOperation.difference, fullRect, polyPath);
    canvas.drawPath(outside, Paint()..color = Colors.black.withOpacity(0.55));

    // Gold Perspective Outline
    canvas.drawPath(
      polyPath,
      Paint()
        ..color = kGoldAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8,
    );

    // Internal Rule-of-Thirds Perspective Grid Lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 1;
    for (int i = 1; i <= 2; i++) {
      final t = i / 3.0;
      final topPt = Offset.lerp(pts[0], pts[1], t)!;
      final botPt = Offset.lerp(pts[3], pts[2], t)!;
      canvas.drawLine(topPt, botPt, gridPaint);

      final leftPt = Offset.lerp(pts[0], pts[3], t)!;
      final rightPt = Offset.lerp(pts[1], pts[2], t)!;
      canvas.drawLine(leftPt, rightPt, gridPaint);
    }

    // Draw 4 Corner Pins
    for (int i = 0; i < 4; i++) {
      final isCurrent = activeCorner == i;
      canvas.drawCircle(
        pts[i],
        isCurrent ? 16 : 12,
        Paint()..color = kNavyPrimary,
      );
      canvas.drawCircle(
        pts[i],
        isCurrent ? 16 : 12,
        Paint()
          ..color = kGoldAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5,
      );
      canvas.drawCircle(pts[i], 4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _PerspectiveCropGridPainter oldDelegate) => true;
}

class _MagnifierLoupePainter extends CustomPainter {
  final ui.Image image;
  final Offset normalizedCenter;

  _MagnifierLoupePainter({required this.image, required this.normalizedCenter});

  @override
  void paint(Canvas canvas, Size size) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final cx = normalizedCenter.dx * imgW;
    final cy = normalizedCenter.dy * imgH;
    final cropRadius = math.min(imgW, imgH) * 0.08;

    final srcRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: cropRadius * 2,
      height: cropRadius * 2,
    );
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, srcRect, dstRect, Paint());

    // Crosshair inside Loupe
    final crossPaint = Paint()
      ..color = kGoldAccent
      ..strokeWidth = 1.8;
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), crossPaint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), crossPaint);
  }

  @override
  bool shouldRepaint(covariant _MagnifierLoupePainter oldDelegate) => true;
}

// =============================================================================
// 6. PDFELEMENT-STYLE IN-PLACE SELECTABLE OCR OVERLAY SCREEN
//    (Select text directly on the picture without jumping to a separate screen!)
// =============================================================================

class InPlaceSelectableOcrScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final bool initialHindi;
  final ValueChanged<List<OcrWordBox>>? onOcrCompleted;

  const InPlaceSelectableOcrScreen({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    this.initialHindi = false,
    this.onOcrCompleted,
  });

  @override
  State<InPlaceSelectableOcrScreen> createState() => _InPlaceSelectableOcrScreenState();
}

class _InPlaceSelectableOcrScreenState extends State<InPlaceSelectableOcrScreen> {
  List<OcrWordBox> _wordBoxes = [];
  final Set<int> _selectedIndices = {};
  bool _runningOcr = true;
  late bool _useHindi;

  @override
  void initState() {
    super.initState();
    _useHindi = widget.initialHindi;
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
    await tmpFile.writeAsBytes(widget.imageBytes);

    final recognizer = TextRecognizer(
      script: _useHindi ? TextRecognitionScript.devanagari : TextRecognitionScript.latin,
    );

    try {
      final recognized = await recognizer.processImage(InputImage.fromFilePath(tmpFile.path));
      final List<OcrWordBox> boxes = [];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            boxes.add(
              OcrWordBox(
                text: element.text,
                boundingBox: element.boundingBox,
              ),
            );
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

  String get _selectedTextString {
    final sorted = _selectedIndices.toList()..sort();
    return sorted.map((i) => _wordBoxes[i].text).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('In-Place Visual OCR Selection', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
            Text('Tap or drag across words directly on the image to select', style: TextStyle(fontSize: 11, color: kGoldAccent)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              setState(() => _useHindi = !_useHindi);
              _performInPlaceOcr();
            },
            icon: const Icon(Icons.translate, color: Colors.white, size: 18),
            label: Text(
              _useHindi ? 'Hindi+Eng' : 'English',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Select All Words on Page',
            icon: const Icon(Icons.select_all),
            onPressed: () {
              setState(() {
                if (_selectedIndices.length == _wordBoxes.length) {
                  _selectedIndices.clear();
                } else {
                  _selectedIndices.addAll(List.generate(_wordBoxes.length, (i) => i));
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_runningOcr)
            const LinearProgressIndicator(color: kGoldAccent),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.imageWidth / math.max(1, widget.imageHeight),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scaleX = constraints.maxWidth / widget.imageWidth;
                    final scaleY = constraints.maxHeight / widget.imageHeight;

                    return GestureDetector(
                      onPanUpdate: (details) {
                        final pt = details.localPosition;
                        for (int i = 0; i < _wordBoxes.length; i++) {
                          final r = _wordBoxes[i].boundingBox;
                          final scaledRect = Rect.fromLTRB(
                            r.left * scaleX,
                            r.top * scaleY,
                            r.right * scaleX,
                            r.bottom * scaleY,
                          );
                          if (scaledRect.inflate(4).contains(pt)) {
                            setState(() => _selectedIndices.add(i));
                          }
                        }
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(widget.imageBytes, fit: BoxFit.fill),
                          // Transparent Interactive Word Bounding Boxes Mapped Directly Over Image
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
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedIndices.remove(i);
                                    } else {
                                      _selectedIndices.add(i);
                                    }
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF2563EB).withOpacity(0.42)
                                        : kGoldAccent.withOpacity(0.14),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF60A5FA)
                                          : kGoldAccent.withOpacity(0.55),
                                      width: isSelected ? 1.5 : 0.7,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          // Floating Selection Bar at Bottom
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            color: kNavySecondary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedIndices.isEmpty
                      ? 'Detected ${_wordBoxes.length} words on page. Tap or drag over words on the picture to copy.'
                      : 'Selected (${_selectedIndices.length} words): $_selectedTextString',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                        ),
                        onPressed: _selectedIndices.isEmpty
                            ? null
                            : () => setState(() => _selectedIndices.clear()),
                        icon: const Icon(Icons.clear, size: 16),
                        label: const Text('Clear Selection'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kGoldAccent,
                          foregroundColor: kNavyPrimary,
                        ),
                        onPressed: _selectedIndices.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: _selectedTextString));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Copied selected text from image!')),
                                );
                              },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy Selected Text', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
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
// 7. COMPLETE ACROBAT & SCAN DOCUMENT STUDIO
//    (Filters, Crop, In-Place OCR, Signature Pad, Stamps, White-Out, Reorder)
// =============================================================================

class AcrobatDocumentStudioScreen extends StatefulWidget {
  final List<EditableDocumentPage> initialPages;
  final String initialTitle;
  final int defaultQuality;
  final bool preferHindiOcr;
  final String? existingFilePath;
  final Future<void> Function(Uint8List pdfBytes, String fileName) onSaveDocument;

  const AcrobatDocumentStudioScreen({
    super.key,
    required this.initialPages,
    required this.initialTitle,
    required this.defaultQuality,
    required this.preferHindiOcr,
    this.existingFilePath,
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
  bool _compilingPdf = false;
  bool _embedSearchableOcrLayer = true;

  @override
  void initState() {
    super.initState();
    _pages = List.from(widget.initialPages);
    _quality = widget.defaultQuality;
    _titleCtrl = TextEditingController(text: widget.initialTitle);
  }

  EditableDocumentPage get _currentPage => _pages[_currentIndex];

  Future<void> _applyFilterToCurrentPage(ScanColorFilter filter) async {
    final page = _currentPage;
    if (filter == ScanColorFilter.original) {
      setState(() {
        page.activeFilter = filter;
        page.displayBytes = page.originalBytes;
      });
      return;
    }

    final decoded = img.decodeImage(page.originalBytes);
    if (decoded == null) return;

    img.Image working = decoded.clone();
    if (filter == ScanColorFilter.grayscale) {
      working = img.grayscale(working);
    } else if (filter == ScanColorFilter.magicColor) {
      working = img.adjustColor(working, contrast: 1.32, saturation: 1.20, brightness: 1.05);
    } else if (filter == ScanColorFilter.highContrastBW) {
      working = img.grayscale(working);
      working = img.luminanceThreshold(working, threshold: 0.52);
    }

    final encoded = Uint8List.fromList(img.encodeJpg(working, quality: 92));
    setState(() {
      page.activeFilter = filter;
      page.displayBytes = encoded;
    });
  }

  Future<void> _openSignaturePadModal() async {
    final List<Offset?> points = [];
    final sigBytes = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          height: 360,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Draw Executive Ink Signature', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  TextButton(onPressed: () => setModal(() => points.clear()), child: const Text('Clear')),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: kSurfaceBg,
                    border: Border.all(color: const Color(0xFF94A3B8)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: GestureDetector(
                    onPanUpdate: (d) => setModal(() => points.add(d.localPosition)),
                    onPanEnd: (_) => setModal(() => points.add(null)),
                    child: CustomPaint(
                      painter: _InkSignaturePainter(points: points),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final recorder = ui.PictureRecorder();
                    final canvas = Canvas(recorder);
                    _InkSignaturePainter(points: points).paint(canvas, const Size(400, 180));
                    final pic = recorder.endRecording();
                    final uiImg = await pic.toImage(400, 180);
                    final byteData = await uiImg.toByteData(format: ui.ImageByteFormat.png);
                    if (ctx.mounted) {
                      Navigator.pop(ctx, byteData?.buffer.asUint8List());
                    }
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Stamp Signature onto Page'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (sigBytes != null) {
      setState(() {
        _currentPage.annotations.add(
          PageAnnotationItem(
            type: 'signature',
            normalizedPos: const Offset(0.68, 0.82),
            signaturePng: sigBytes,
          ),
        );
      });
    }
  }

  Future<void> _openExecutiveStampSelector() async {
    final stamps = [
      ('APPROVED', const Color(0xFF15803D)),
      ('PAID IN FULL', const Color(0xFF1D4ED8)),
      ('CONFIDENTIAL', const Color(0xFFDC2626)),
      ('VERIFIED BY AN SCAN', const Color(0xFFB45309)),
    ];

    await showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Apply Official Executive Stamp or Watermark', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: stamps.map((s) {
                return ActionChip(
                  label: Text(s.$1, style: TextStyle(color: s.$2, fontWeight: FontWeight.w900)),
                  side: BorderSide(color: s.$2, width: 1.5),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _currentPage.annotations.add(
                        PageAnnotationItem(
                          type: 'stamp',
                          text: s.$1,
                          color: s.$2,
                          normalizedPos: const Offset(0.65, 0.72),
                        ),
                      );
                    });
                  },
                );
              }).toList(),
            ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('Apply White-Out Eraser Patch'),
              subtitle: const Text('Covers unwanted text or marks on the page'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _currentPage.annotations.add(
                    PageAnnotationItem(
                      type: 'whiteout',
                      normalizedPos: const Offset(0.5, 0.5),
                    ),
                  );
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Compiles all pages into a final PDF with an embedded invisible selectable OCR layer (PDFelement style!)
  Future<void> _compileAndSaveFinalPdf() async {
    setState(() => _compilingPdf = true);

    try {
      final pdf = pw.Document();
      final recognizer = TextRecognizer(
        script: widget.preferHindiOcr ? TextRecognitionScript.devanagari : TextRecognitionScript.latin,
      );
      final tmpDir = await getTemporaryDirectory();

      for (int i = 0; i < _pages.length; i++) {
        final pItem = _pages[i];
        final compressed = await FlutterImageCompress.compressWithList(
          pItem.displayBytes,
          quality: _quality,
          rotate: pItem.rotationQuarterTurns * 90,
        );

        // If user enabled Searchable PDF Layer and OCR hasn't run on this page yet, run it automatically
        if (_embedSearchableOcrLayer && pItem.ocrWords.isEmpty) {
          final tmpFile = File(p.join(tmpDir.path, 'pdf_ocr_$i.jpg'));
          await tmpFile.writeAsBytes(compressed);
          final recognized = await recognizer.processImage(InputImage.fromFilePath(tmpFile.path));
          for (final block in recognized.blocks) {
            for (final line in block.lines) {
              for (final el in line.elements) {
                pItem.ocrWords.add(OcrWordBox(text: el.text, boundingBox: el.boundingBox));
              }
            }
          }
        }

        final pageW = PdfPageFormat.a4.width;
        final pageH = PdfPageFormat.a4.height;
        final scaleX = pageW / math.max(1, pItem.imageWidth);
        final scaleY = pageH / math.max(1, pItem.imageHeight);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.Image(pw.MemoryImage(compressed), fit: pw.BoxFit.fill),
                ),
                // Invisible Selectable Text Layer Mapped to Exact Coordinates (PDFelement / Acrobat Pro style)
                ...pItem.ocrWords.map((wb) {
                  return pw.Positioned(
                    left: wb.boundingBox.left * scaleX,
                    top: wb.boundingBox.top * scaleY,
                    child: pw.Opacity(
                      opacity: 0.01,
                      child: pw.Text(
                        wb.text,
                        style: pw.TextStyle(
                          fontSize: math.max(6, wb.boundingBox.height * scaleY * 0.8),
                        ),
                      ),
                    ),
                  );
                }),
                // Render Stamps, Whiteout & Signatures onto PDF Page
                ...pItem.annotations.map((ann) {
                  final dx = (ann.normalizedPos.dx * pageW).clamp(10.0, pageW - 120.0);
                  final dy = (ann.normalizedPos.dy * pageH).clamp(10.0, pageH - 60.0);
                  if (ann.type == 'whiteout') {
                    return pw.Positioned(
                      left: dx,
                      top: dy,
                      child: pw.Container(width: 110, height: 32, color: PdfColors.white),
                    );
                  } else if (ann.type == 'signature' && ann.signaturePng != null) {
                    return pw.Positioned(
                      left: dx,
                      top: dy,
                      child: pw.Image(pw.MemoryImage(ann.signaturePng!), width: 130, height: 60),
                    );
                  } else {
                    return pw.Positioned(
                      left: dx,
                      top: dy,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.red800, width: 2),
                        ),
                        child: pw.Text(
                          ann.text,
                          style: pw.TextStyle(
                            color: PdfColors.red800,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }
                }),
              ],
            ),
          ),
        );
      }

      await recognizer.close();
      final finalBytes = await pdf.save();
      await widget.onSaveDocument(finalBytes, _titleCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved Searchable PDF to AN Scan Vault!'),
            backgroundColor: Color(0xFF15803D),
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _compilingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('Page ${_currentIndex + 1} of ${_pages.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Add Another Camera Page',
            icon: const Icon(Icons.add_a_photo_outlined, color: kGoldAccent),
            onPressed: () async {
              final shot = await ImagePicker().pickImage(source: ImageSource.camera);
              if (shot != null) {
                final bytes = await File(shot.path).readAsBytes();
                final dec = img.decodeImage(bytes);
                setState(() {
                  _pages.add(
                    EditableDocumentPage(
                      originalBytes: bytes,
                      displayBytes: bytes,
                      imageWidth: dec?.width ?? 1000,
                      imageHeight: dec?.height ?? 1400,
                    ),
                  );
                  _currentIndex = _pages.length - 1;
                });
              }
            },
          ),
          IconButton(
            tooltip: 'Delete Current Page',
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () {
              setState(() {
                _pages.removeAt(_currentIndex);
                if (_currentIndex >= _pages.length && _currentIndex > 0) {
                  _currentIndex--;
                }
              });
              if (_pages.isEmpty) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Document Name & Searchable OCR Toggle Bar
          Container(
            color: kNavySecondary,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleCtrl,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Document Title',
                      labelStyle: TextStyle(color: kGoldAccent, fontSize: 11),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilterChip(
                  label: const Text('Searchable OCR', style: TextStyle(fontSize: 11.5)),
                  selected: _embedSearchableOcrLayer,
                  onSelected: (v) => setState(() => _embedSearchableOcrLayer = v),
                ),
              ],
            ),
          ),
          // Interactive Page Canvas with Draggable Stamps, Signatures & Whiteout
          Expanded(
            child: PageView.builder(
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, pageIdx) {
                final page = _pages[pageIdx];
                return Padding(
                  padding: const EdgeInsets.all(14),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          RotatedBox(
                            quarterTurns: page.rotationQuarterTurns,
                            child: Image.memory(page.displayBytes, fit: BoxFit.contain),
                          ),
                          // Draggable Annotations (Stamps, Signatures, White-Out)
                          ...List.generate(page.annotations.length, (annIdx) {
                            final ann = page.annotations[annIdx];
                            return Positioned(
                              left: ann.normalizedPos.dx * constraints.maxWidth - 50,
                              top: ann.normalizedPos.dy * constraints.maxHeight - 20,
                              child: GestureDetector(
                                onPanUpdate: (d) {
                                  setState(() {
                                    final newX = (ann.normalizedPos.dx + d.delta.dx / constraints.maxWidth).clamp(0.05, 0.95);
                                    final newY = (ann.normalizedPos.dy + d.delta.dy / constraints.maxHeight).clamp(0.05, 0.95);
                                    page.annotations[annIdx] = PageAnnotationItem(
                                      type: ann.type,
                                      text: ann.text,
                                      color: ann.color,
                                      signaturePng: ann.signaturePng,
                                      normalizedPos: Offset(newX, newY),
                                    );
                                  });
                                },
                                onLongPress: () {
                                  setState(() => page.annotations.removeAt(annIdx));
                                },
                                child: _buildAnnotationWidget(ann),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
          // Filter Strip
          Container(
            height: 44,
            color: kNavySecondary,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: ScanColorFilter.values.map((f) {
                final selected = _currentPage.activeFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.label, style: const TextStyle(fontSize: 11.5)),
                    selected: selected,
                    onSelected: (_) => _applyFilterToCurrentPage(f),
                  ),
                );
              }).toList(),
            ),
          ),
          // Acrobat & Scan Action Toolbar (4-Corner Crop, In-Place OCR, Rotate, Sign, Stamp)
          Container(
            color: kNavyPrimary,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _studioActionBtn(
                        icon: Icons.crop_free,
                        label: '4-Corner Crop',
                        onTap: () async {
                          final warped = await Navigator.push<Uint8List>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FourCornerPerspectiveCropScreen(
                                imageBytes: _currentPage.originalBytes,
                                pageTitle: '4-Corner Perspective Crop',
                              ),
                            ),
                          );
                          if (warped != null) {
                            setState(() {
                              _currentPage.originalBytes = warped;
                              _currentPage.displayBytes = warped;
                            });
                          }
                        },
                      ),
                      _studioActionBtn(
                        icon: Icons.text_Snippet_outlined,
                        fallback: Icons.manage_search_rounded,
                        label: 'In-Place OCR',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InPlaceSelectableOcrScreen(
                                imageBytes: _currentPage.displayBytes,
                                imageWidth: _currentPage.imageWidth,
                                imageHeight: _currentPage.imageHeight,
                                initialHindi: widget.preferHindiOcr,
                                onOcrCompleted: (words) {
                                  _currentPage.ocrWords = words;
                                },
                              ),
                            ),
                          );
                        },
                      ),
                      _studioActionBtn(
                        icon: Icons.rotate_right,
                        label: 'Rotate 90°',
                        onTap: () {
                          setState(() {
                            _currentPage.rotationQuarterTurns = (_currentPage.rotationQuarterTurns + 1) % 4;
                          });
                        },
                      ),
                      _studioActionBtn(
                        icon: Icons.draw_outlined,
                        label: 'Sign Ink',
                        onTap: _openSignaturePadModal,
                      ),
                      _studioActionBtn(
                        icon: Icons.approval_outlined,
                        label: 'Stamp / Erase',
                        onTap: _openExecutiveStampSelector,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Quality:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _quality.toDouble(),
                        min: 30,
                        max: 100,
                        divisions: 7,
                        activeColor: kGoldAccent,
                        label: '$_quality%',
                        onChanged: (v) => setState(() => _quality = v.round()),
                      ),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: kGoldAccent,
                        foregroundColor: kNavyPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onPressed: _compilingPdf ? null : _compileAndSaveFinalPdf,
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: Text(
                        _compilingPdf ? 'Compiling...' : 'Save PDF',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _studioActionBtn({
    required IconData icon,
    IconData? fallback,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white24),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onPressed: onTap,
        icon: Icon(fallback ?? icon, size: 17, color: kGoldAccent),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _buildAnnotationWidget(PageAnnotationItem ann) {
    if (ann.type == 'whiteout') {
      return Container(
        width: 110,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade400, width: 1),
        ),
      );
    } else if (ann.type == 'signature' && ann.signaturePng != null) {
      return Image.memory(ann.signaturePng!, width: 130, height: 60);
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: ann.color, width: 2.2),
          borderRadius: BorderRadius.circular(4),
          color: Colors.white.withOpacity(0.85),
        ),
        child: Text(
          ann.text,
          style: TextStyle(color: ann.color, fontWeight: FontWeight.w900, fontSize: 12),
        ),
      );
    }
  }
}

class _InkSignaturePainter extends CustomPainter {
  final List<Offset?> points;
  _InkSignaturePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kNavyPrimary
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InkSignaturePainter oldDelegate) => true;
}
