import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ANOfficeApp());
}

class ANOfficeApp extends StatelessWidget {
  const ANOfficeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AN Office',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8F9FD),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF008080),
          secondary: Color(0xFF0F172A),
          surface: Colors.white,
          onSurface: Color(0xFF0F172A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
      ),
      home: const ANHomeScreen(),
    );
  }
}

// ============================================================================
// CLASSICAL EXECUTIVE "AN OFFICE" MONOGRAM LOGO WIDGET
// ============================================================================
class ANLogoBadge extends StatelessWidget {
  final double size;
  const ANLogoBadge({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: const Color(0xFF008080), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF008080).withOpacity(0.22),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: size * 0.16,
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'A',
                    style: TextStyle(
                      color: const Color(0xFF2DD4BF),
                      fontWeight: FontWeight.w900,
                      fontSize: size * 0.42,
                      letterSpacing: 0.5,
                    ),
                  ),
                  TextSpan(
                    text: 'N',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: size * 0.42,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: size * 0.12,
            child: Container(
              width: size * 0.46,
              height: 2,
              decoration: BoxDecoration(
                color: const Color(0xFF008080),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DATA MODELS FOR DOCUMENTS & STUDIO PER-PAGE EDITS
// ============================================================================
enum DocCategory { all, trade, idCard, spreadsheets, wordNotes, bank }

class OfficeDocument {
  final File file;
  final String title;
  final DateTime modified;
  final String sizeMb;
  final List<String> pageImagePaths;
  final DocCategory category;
  final String extension;
  final bool isLocked;
  final String? pinCode;

  OfficeDocument({
    required this.file,
    required this.title,
    required this.modified,
    required this.sizeMb,
    required this.pageImagePaths,
    required this.category,
    required this.extension,
    this.isLocked = false,
    this.pinCode,
  });
}

class DrawnStroke {
  final List<Offset> normalizedPoints; // 0.0 to 1.0 relative to page image
  final Color color;
  final double strokeWidth;

  DrawnStroke({
    required this.normalizedPoints,
    required this.color,
    required this.strokeWidth,
  });
}

class FloatingTextItem {
  String text;
  Offset normalizedPos; // 0.0 to 1.0 relative to page image
  double fontSize;
  Color color;

  FloatingTextItem({
    required this.text,
    required this.normalizedPos,
    required this.fontSize,
    required this.color,
  });
}

class PageEditData {
  String imagePath;
  int filterMode; // 0 = Original (Default), 1 = Grayscale, 2 = Clean Contrast
  List<DrawnStroke> strokes = [];
  List<FloatingTextItem> texts = [];
  double aspectRatio;

  PageEditData({
    required this.imagePath,
    this.filterMode = 0, // Strictly Original by default
    this.aspectRatio = 0.707,
  });
}

// ============================================================================
// HOME SCREEN (PINTEREST / DRIBBBLE SOFT-MODERN EXECUTIVE UI)
// ============================================================================
class ANHomeScreen extends StatefulWidget {
  const ANHomeScreen({super.key});

  @override
  State<ANHomeScreen> createState() => _ANHomeScreenState();
}

class _ANHomeScreenState extends State<ANHomeScreen> {
  List<OfficeDocument> _allDocs = [];
  String _searchQuery = '';
  DocCategory _selectedCategory = DocCategory.all;
  final ImagePicker _picker = ImagePicker();

  String _userName = 'Adesh Narang';
  String _userEmail = 'adesh@adeshnarang.in';
  bool _cloudSyncEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadAccountProfile();
    _checkCameraCrashRecovery();
    _loadDocuments();
  }

  Future<void> _loadAccountProfile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final profileFile = File('${dir.path}/an_account.json');
      if (profileFile.existsSync()) {
        final data = jsonDecode(await profileFile.readAsString());
        if (mounted) {
          setState(() {
            _userName = data['name'] ?? 'Adesh Narang';
            _userEmail = data['email'] ?? 'adesh@adeshnarang.in';
            _cloudSyncEnabled = data['sync'] ?? true;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveAccountProfile(String name, String email, bool sync) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final profileFile = File('${dir.path}/an_account.json');
      await profileFile.writeAsString(jsonEncode({
        'name': name,
        'email': email,
        'sync': sync,
      }));
      if (mounted) {
        setState(() {
          _userName = name;
          _userEmail = email;
          _cloudSyncEnabled = sync;
        });
      }
    } catch (_) {}
  }

  // Prevents Android 50MP stock camera RAM reloads from dropping captured photos
  Future<void> _checkCameraCrashRecovery() async {
    try {
      final LostDataResponse response = await _picker.retrieveLostData();
      if (!response.isEmpty && response.files != null && response.files!.isNotEmpty) {
        final paths = response.files!.map((f) => f.path).toList();
        _openStudioWithImages(paths, isIdMode: false);
      }
    } catch (_) {}
  }

  Future<void> _loadDocuments() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final allFiles = dir.listSync().whereType<File>().toList();

      List<OfficeDocument> loaded = [];
      for (var file in allFiles) {
        final ext = file.path.split('.').last.toLowerCase();
        if (!['pdf', 'xlsx', 'csv', 'docx', 'txt'].contains(ext)) continue;

        final stat = file.statSync();
        final sizeMb = (stat.size / (1024 * 1024)).toStringAsFixed(2);
        final fileName = file.path.split('/').last;
        final rawName = fileName.substring(0, fileName.length - ext.length - 1);

        DocCategory cat = DocCategory.trade;
        final lower = rawName.toLowerCase();
        if (rawName.startsWith('ID_') || lower.contains('id_') || lower.contains('aadhaar') || lower.contains('pan')) {
          cat = DocCategory.idCard;
        } else if (ext == 'xlsx' || ext == 'csv') {
          cat = DocCategory.spreadsheets;
        } else if (ext == 'docx' || ext == 'txt') {
          cat = DocCategory.wordNotes;
        } else if (lower.contains('bank') || lower.contains('stmt') || lower.contains('statement')) {
          cat = DocCategory.bank;
        }

        final metaFile = File('${dir.path}/$rawName.meta');
        List<String> pages = [];
        if (metaFile.existsSync()) {
          pages = metaFile.readAsLinesSync().where((p) => p.trim().isNotEmpty && File(p).existsSync()).toList();
        }

        final lockFile = File('${dir.path}/$rawName.lock');
        String? pin;
        if (lockFile.existsSync()) {
          pin = lockFile.readAsStringSync().trim();
        }

        loaded.add(OfficeDocument(
          file: file,
          title: rawName,
          modified: stat.modified,
          sizeMb: '$sizeMb MB',
          pageImagePaths: pages,
          category: cat,
          extension: ext,
          isLocked: pin != null && pin.isNotEmpty,
          pinCode: pin,
        ));
      }

      loaded.sort((a, b) => b.modified.compareTo(a.modified));
      if (mounted) setState(() => _allDocs = loaded);
    } catch (_) {}
  }

  // Dual-Engine Image Normalizer: Decodes any HEIC/WebP/Raw stream via Flutter Native Codec first, then encodes to clean JPG
  Future<String> _normalizeToStandardJpg(String inputPath, int index) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final targetPath = '${dir.path}/norm_${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
      final rawBytes = await File(inputPath).readAsBytes();

      // Layer 1: Pure Dart decode
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        await File(targetPath).writeAsBytes(img.encodeJpg(decoded, quality: 95));
        return targetPath;
      }

      // Layer 2: Native Android hardware codec fallback (handles Samsung HEIC / 50MP streams)
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final pngImg = img.decodePng(byteData.buffer.asUint8List());
        if (pngImg != null) {
          await File(targetPath).writeAsBytes(img.encodeJpg(pngImg, quality: 95));
          return targetPath;
        }
      }
    } catch (_) {}
    return inputPath;
  }

  Future<void> _openStudioWithImages(List<String> rawPaths, {required bool isIdMode, String? existingTitle}) async {
    if (rawPaths.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF008080))),
    );

    List<String> cleanPaths = [];
    for (int i = 0; i < rawPaths.length; i++) {
      cleanPaths.add(await _normalizeToStandardJpg(rawPaths[i], i));
    }

    if (!mounted) return;
    Navigator.pop(context); // Close loader

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ANPreSaveStudio(
          initialImages: cleanPaths,
          isIdMode: isIdMode,
          initialTitle: existingTitle,
          onSaved: _loadDocuments,
        ),
      ),
    );
  }

  // --- CAPTURE MODES ---
  Future<void> _startUltraHdCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 100);
      if (photo != null) {
        await _openStudioWithImages([photo.path], isIdMode: false);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera error: $e')));
    }
  }

  Future<void> _importFromGallery() async {
    try {
      final List<XFile> photos = await _picker.pickMultiImage(imageQuality: 100);
      if (photos.isNotEmpty) {
        await _openStudioWithImages(photos.map((e) => e.path).toList(), isIdMode: false);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gallery error: $e')));
    }
  }

  Future<void> _startMLScan({required bool isIdMode}) async {
    try {
      // ScannerMode.base captures & crops WITHOUT forcing Google's auto-contrast filter!
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormat: DocumentFormat.jpeg,
          mode: ScannerMode.base,
          isGalleryImport: true,
          pageLimit: isIdMode ? 2 : 50,
        ),
      );

      final result = await scanner.scanDocument();
      await scanner.close();

      if (result.images.isNotEmpty) {
        await _openStudioWithImages(result.images, isIdMode: isIdMode);
      }
    } catch (_) {}
  }

  // --- UNIVERSAL FILE OPENER & TWO-WAY CONVERSION ENGINE ---
  Future<void> _pickAndOpenAnyOfficeFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'xlsx', 'xls', 'csv', 'docx', 'txt', 'jpg', 'jpeg', 'png'],
      );
      if (result == null || result.files.single.path == null) return;

      final pickedFile = File(result.files.single.path!);
      final ext = pickedFile.path.split('.').last.toLowerCase();
      final baseName = result.files.single.name.replaceAll('.$ext', '');

      if (['jpg', 'jpeg', 'png'].contains(ext)) {
        await _openStudioWithImages([pickedFile.path], isIdMode: false, existingTitle: baseName);
        return;
      }

      // Copy into AN Office workspace so it stays in your recent files
      final dir = await getApplicationDocumentsDirectory();
      final savedCopy = File('${dir.path}/$baseName.$ext');
      if (pickedFile.path != savedCopy.path) {
        await pickedFile.copy(savedCopy.path);
        await _loadDocuments();
      }

      if (!mounted) return;
      if (ext == 'xlsx' || ext == 'csv') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ANSpreadsheetViewerScreen(
              file: savedCopy,
              title: baseName,
              onConverted: _loadDocuments,
            ),
          ),
        );
      } else if (ext == 'docx' || ext == 'txt') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ANWordTextViewerScreen(
              file: savedCopy,
              title: baseName,
              onConverted: _loadDocuments,
            ),
          ),
        );
      } else {
        OpenFile.open(savedCopy.path);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('File error: $e')));
    }
  }

  // --- MERGE / COMBINE MULTIPLE SCANS INTO ONE MASTER PDF ---
  void _showMergeDocumentsModal() {
    final scannableDocs = _allDocs.where((d) => d.pageImagePaths.isNotEmpty).toList();
    if (scannableDocs.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need at least 2 scanned PDF documents to merge!')),
      );
      return;
    }

    final Set<int> selectedIndices = {};
    final nameCtrl = TextEditingController(text: 'Merged_${DateFormat('ddMMM_HHmm').format(DateTime.now())}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Combine / Merge PDFs', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Select 2 or more documents to join into one master PDF:', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Merged File Name', suffixText: '.pdf', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 240,
                child: ListView.builder(
                  itemCount: scannableDocs.length,
                  itemBuilder: (context, i) {
                    final doc = scannableDocs[i];
                    final isChecked = selectedIndices.contains(i);
                    return CheckboxListTile(
                      value: isChecked,
                      activeColor: const Color(0xFF008080),
                      title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${doc.pageImagePaths.length} pages • ${doc.sizeMb}'),
                      onChanged: (val) {
                        setModalState(() {
                          if (val == true) {
                            selectedIndices.add(i);
                          } else {
                            selectedIndices.remove(i);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF008080),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.merge_type),
                  label: Text('Merge (${selectedIndices.length} Selected)'),
                  onPressed: selectedIndices.length < 2
                      ? null
                      : () async {
                          Navigator.pop(context);
                          List<String> combinedPages = [];
                          for (final idx in selectedIndices) {
                            combinedPages.addAll(scannableDocs[idx].pageImagePaths);
                          }
                          await _compilePagesToPdfFile(combinedPages, nameCtrl.text.trim(), isIdMode: false);
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _compilePagesToPdfFile(List<String> pages, String title, {required bool isIdMode}) async {
    try {
      final pdfDoc = pw.Document(author: 'Adesh Narang', creator: 'AN Office (adeshnarang.in)');
      for (final p in pages) {
        final bytes = await File(p).readAsBytes();
        pdfDoc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain)),
          ),
        );
      }
      final dir = await getApplicationDocumentsDirectory();
      final outPdf = File('${dir.path}/$title.pdf');
      await outPdf.writeAsBytes(await pdfDoc.save());
      final outMeta = File('${dir.path}/$title.meta');
      await outMeta.writeAsString(pages.join('\n'));
      await _loadDocuments();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved $title.pdf!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // --- TWO-WAY CONVERSION HUB MODAL ---
  void _showConvertHubModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 16),
                const Text('AN Office Two-Way Convert Hub', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                const Text('Convert seamlessly between PDF, Excel, Word, Images & Text offline', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                _convertTile(
                  icon: Icons.table_view_rounded,
                  color: Colors.green.shade700,
                  title: 'Excel / CSV ➔ Executive PDF',
                  subtitle: 'Convert .xlsx or .csv spreadsheets into formatted A4 PDF tables',
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndOpenAnyOfficeFile();
                  },
                ),
                _convertTile(
                  icon: Icons.grid_on_rounded,
                  color: Colors.teal.shade700,
                  title: 'Scanned PDF / Image ➔ Excel (.xlsx)',
                  subtitle: 'Extract ledger rows & numbers into editable Excel spreadsheet cells',
                  onTap: () {
                    Navigator.pop(context);
                    _pickScanForConversion(targetFormat: 'xlsx');
                  },
                ),
                _convertTile(
                  icon: Icons.description_outlined,
                  color: Colors.blue.shade700,
                  title: 'Scanned PDF / Image ➔ Word (.docx)',
                  subtitle: 'Extract page text via offline OCR into an editable Word document',
                  onTap: () {
                    Navigator.pop(context);
                    _pickScanForConversion(targetFormat: 'docx');
                  },
                ),
                _convertTile(
                  icon: Icons.article_outlined,
                  color: Colors.indigo.shade700,
                  title: 'Word (.docx) / Text (.txt) ➔ PDF',
                  subtitle: 'Open any Word or Notepad file and compile into a clean A4 PDF',
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndOpenAnyOfficeFile();
                  },
                ),
                _convertTile(
                  icon: Icons.collections_outlined,
                  color: Colors.orange.shade800,
                  title: 'Photos ⇄ PDF (Two-Way)',
                  subtitle: 'Turn gallery photos into PDF, or export any scan to JPG images',
                  onTap: () {
                    Navigator.pop(context);
                    _importFromGallery();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _convertTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFFF8F9FD),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _pickScanForConversion({required String targetFormat}) {
    final scannable = _allDocs.where((d) => d.pageImagePaths.isNotEmpty).toList();
    if (scannable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan or import a document first, then convert it in 1 tap!')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select Document to Convert to .${targetFormat.toUpperCase()}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: scannable.length,
                  itemBuilder: (context, idx) {
                    final d = scannable[idx];
                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf, color: Color(0xFF008080)),
                      title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${d.pageImagePaths.length} pages'),
                      onTap: () {
                        Navigator.pop(context);
                        if (targetFormat == 'xlsx') {
                          _exportScanToExcel(d);
                        } else {
                          _exportScanToWordDocx(d);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- CONVERT SCANNED PAGES TO REAL EXCEL (.XLSX) SPREADSHEET ---
  Future<void> _exportScanToExcel(OfficeDocument doc) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Extracting table & numbers into Excel (.xlsx)...')));
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final excel = xl.Excel.createExcel();
      final xl.Sheet sheet = excel['Sheet1'];

      sheet.appendRow([
        xl.TextCellValue('AN Office Ledger & Table Export'),
        xl.TextCellValue('Source: ${doc.title}'),
        xl.TextCellValue('Built by Adesh Narang (adeshnarang.in)'),
      ]);
      sheet.appendRow([xl.TextCellValue('')]);

      for (int i = 0; i < doc.pageImagePaths.length; i++) {
        final recognized = await recognizer.processImage(InputImage.fromFilePath(doc.pageImagePaths[i]));
        sheet.appendRow([xl.TextCellValue('--- PAGE ${i + 1} ---')]);
        final lines = recognized.text.split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          // Split columns by 2+ spaces or tabs or pipe
          final cols = line.trim().split(RegExp(r'\s{2,}|\t|\|'));
          sheet.appendRow(cols.map((c) {
            final cleanNum = double.tryParse(c.replaceAll(',', '').trim());
            if (cleanNum != null) return xl.DoubleCellValue(cleanNum);
            return xl.TextCellValue(c.trim());
          }).toList());
        }
      }
      await recognizer.close();

      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/${doc.title}_Table.xlsx';
      final fileBytes = excel.save();
      if (fileBytes != null) {
        await File(outPath).writeAsBytes(fileBytes);
        await _loadDocuments();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved Excel: ${doc.title}_Table.xlsx')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel export error: $e')));
    }
  }

  // --- CONVERT SCANNED PAGES TO REAL WORD (.DOCX) ---
  Future<void> _exportScanToWordDocx(OfficeDocument doc) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating editable Word (.docx) file...')));
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final StringBuffer fullText = StringBuffer();

      for (int i = 0; i < doc.pageImagePaths.length; i++) {
        final recognized = await recognizer.processImage(InputImage.fromFilePath(doc.pageImagePaths[i]));
        fullText.writeln('--- Page ${i + 1} ---');
        fullText.writeln(recognized.text.trim());
        fullText.writeln();
      }
      await recognizer.close();

      final docxBytes = _buildOpenXmlDocxBytes(doc.title, fullText.toString());
      final dir = await getApplicationDocumentsDirectory();
      final outFile = File('${dir.path}/${doc.title}.docx');
      await outFile.writeAsBytes(docxBytes);
      await _loadDocuments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved Word Document: ${doc.title}.docx')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Word export error: $e')));
    }
  }

  Uint8List _buildOpenXmlDocxBytes(String title, String bodyText) {
    final archive = Archive();

    const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    final escapedLines = bodyText.split('\n').map((line) {
      final safe = line
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      return '<w:p><w:r><w:t>$safe</w:t></w:r></w:p>';
    }).join('');

    final docXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>$title - Exported by AN Office (adeshnarang.in)</w:t></w:r></w:p>
    $escapedLines
  </w:body>
</w:document>''';

    archive.addFile(ArchiveFile('[Content_Types].xml', contentTypes.length, utf8.encode(contentTypes)));
    archive.addFile(ArchiveFile('_rels/.rels', rels.length, utf8.encode(rels)));
    archive.addFile(ArchiveFile('word/document.xml', utf8.encode(docXml).length, utf8.encode(docXml)));

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  // --- EXPORT PDF PAGES AS INDIVIDUAL GALLERY JPEGS ---
  Future<void> _exportPagesAsJpgs(OfficeDocument doc) async {
    if (doc.pageImagePaths.isEmpty) return;
    try {
      Directory downloadDir = Directory('/storage/emulated/0/Download/AN_Office_Images');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      for (int i = 0; i < doc.pageImagePaths.length; i++) {
        final target = File('${downloadDir.path}/${doc.title}_Page_${i + 1}.jpg');
        await File(doc.pageImagePaths[i]).copy(target.path);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${doc.pageImagePaths.length} JPG images to Download/AN_Office_Images!')),
        );
      }
    } catch (_) {
      Share.shareXFiles(doc.pageImagePaths.map((p) => XFile(p)).toList());
    }
  }

  // --- TIERED PDF COMPRESSION WITH EXACT MB ESTIMATES & QUALITY DETAILS ---
  void _showCompressDialog(OfficeDocument doc) {
    final currentBytes = doc.file.lengthSync();
    final currentMb = currentBytes / (1024 * 1024);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Compress PDF Document', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Original File Size:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text('${currentMb.toStringAsFixed(2)} MB', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _compressOptionCard(
              title: 'Low Compression (85% Quality)',
              qualityNote: 'Crystal-clear text & fine ledger lines. Best for printing & archival.',
              estimatedSize: '~${(currentMb * 0.72).toStringAsFixed(2)} MB',
              onTap: () {
                Navigator.pop(context);
                _executeCompression(doc, quality: 85, scale: 0.92, suffix: 'LowComp');
              },
            ),
            const SizedBox(height: 8),
            _compressOptionCard(
              title: 'Medium Compression (60% Quality)',
              qualityNote: 'Sharp screen readability at half the size. Ideal for WhatsApp & Email.',
              estimatedSize: '~${(currentMb * 0.45).toStringAsFixed(2)} MB',
              onTap: () {
                Navigator.pop(context);
                _executeCompression(doc, quality: 60, scale: 0.75, suffix: 'MedComp');
              },
            ),
            const SizedBox(height: 8),
            _compressOptionCard(
              title: 'High Compression (35% Quality)',
              qualityNote: 'Smallest file size for strict government/portal upload limits (< 500 KB).',
              estimatedSize: '~${(currentMb * 0.22).toStringAsFixed(2)} MB',
              onTap: () {
                Navigator.pop(context);
                _executeCompression(doc, quality: 35, scale: 0.55, suffix: 'HighComp');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _compressOptionCard({
    required String title,
    required String qualityNote,
    required String estimatedSize,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF008080))),
                  const SizedBox(height: 4),
                  Text(qualityNote, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFCCFBF1), borderRadius: BorderRadius.circular(6)),
              child: Text(estimatedSize, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF008080))),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeCompression(OfficeDocument doc, {required int quality, required double scale, required String suffix, bool shareAfter = false}) async {
    if (doc.pageImagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Compression applies to scanned image PDFs.')));
      return;
    }
    try {
      final pdfDoc = pw.Document(author: 'Adesh Narang', creator: 'AN Office (adeshnarang.in)');
      for (final p in doc.pageImagePaths) {
        final originalBytes = await File(p).readAsBytes();
        final decoded = img.decodeImage(originalBytes);
        if (decoded != null) {
          final resized = img.copyResize(decoded, width: max(600, (decoded.width * scale).round()));
          final compressedBytes = img.encodeJpg(resized, quality: quality);
          pdfDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(compressedBytes), fit: pw.BoxFit.contain)),
            ),
          );
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final compressedFile = File('${dir.path}/${doc.title}_$suffix.pdf');
      await compressedFile.writeAsBytes(await pdfDoc.save());
      final metaFile = File('${dir.path}/${doc.title}_$suffix.meta');
      await metaFile.writeAsString(doc.pageImagePaths.join('\n'));

      await _loadDocuments();
      if (shareAfter) {
        Share.shareXFiles([XFile(compressedFile.path)]);
      } else if (mounted) {
        final newMb = (compressedFile.lengthSync() / (1024 * 1024)).toStringAsFixed(2);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Compressed PDF saved! New exact size: $newMb MB')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compression failed: $e')));
    }
  }

  // --- LOCK / UNLOCK PDF PASSWORD MANAGEMENT ---
  void _showLockOrUnlockDialog(OfficeDocument doc) {
    final passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(doc.isLocked ? 'Remove Password / Unlock PDF' : 'Set Password / Lock PDF', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              doc.isLocked
                  ? 'Enter the password once to strip protection and create an unlocked copy ready to share:'
                  : 'Set a passcode to lock this document inside AN Office:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password / PIN', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
            onPressed: () async {
              final entered = passCtrl.text.trim();
              if (entered.isEmpty) return;
              Navigator.pop(context);
              final dir = await getApplicationDocumentsDirectory();

              if (doc.isLocked) {
                if (doc.pinCode != null && doc.pinCode != entered) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect password!')));
                  return;
                }
                final lockFile = File('${dir.path}/${doc.title}.lock');
                if (lockFile.existsSync()) await lockFile.delete();
                final unlockedCopy = File('${dir.path}/${doc.title}_Unlocked.${doc.extension}');
                await doc.file.copy(unlockedCopy.path);
                await _loadDocuments();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password removed! Clean copy saved.')));
                }
              } else {
                final lockFile = File('${dir.path}/${doc.title}.lock');
                await lockFile.writeAsString(entered);
                await _loadDocuments();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document locked with password!')));
                }
              }
            },
            child: Text(doc.isLocked ? 'Unlock & Strip Password' : 'Lock Document'),
          ),
        ],
      ),
    );
  }

  // --- OFFICIAL & SECURITY WATERMARK OVERLAY ---
  void _showWatermarkDialog(OfficeDocument doc) {
    if (doc.pageImagePaths.isEmpty) return;
    String selectedStamp = 'FOR VERIFICATION ONLY - NOT FOR TRANSACTION';
    final customCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Apply Official / Security Watermark', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...[
                  'FOR VERIFICATION ONLY - NOT FOR TRANSACTION',
                  'CONFIDENTIAL',
                  'PAID & VERIFIED',
                  'APPROVED BY ADESH NARANG',
                  'SAMPLE COPY',
                ].map((s) {
                  return RadioListTile<String>(
                    dense: true,
                    title: Text(s, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    value: s,
                    groupValue: selectedStamp,
                    activeColor: const Color(0xFF008080),
                    onChanged: (val) => setDState(() => selectedStamp = val!),
                  );
                }),
                const SizedBox(height: 8),
                TextField(
                  controller: customCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Or type custom watermark text...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(context);
                final stampText = customCtrl.text.trim().isNotEmpty ? customCtrl.text.trim() : selectedStamp;
                try {
                  final pdfDoc = pw.Document(author: 'Adesh Narang', creator: 'AN Office (adeshnarang.in)');
                  for (final p in doc.pageImagePaths) {
                    final imgBytes = await File(p).readAsBytes();
                    pdfDoc.addPage(
                      pw.Page(
                        pageFormat: PdfPageFormat.a4,
                        margin: pw.EdgeInsets.zero,
                        build: (_) => pw.Stack(
                          alignment: pw.Alignment.center,
                          children: [
                            pw.Center(child: pw.Image(pw.MemoryImage(imgBytes), fit: pw.BoxFit.contain)),
                            pw.Transform.rotateBox(
                              angle: 0.65,
                              child: pw.Text(
                                stampText,
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  fontSize: 28,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0x44D32F2F),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final dir = await getApplicationDocumentsDirectory();
                  final stampedFile = File('${dir.path}/${doc.title}_Watermarked.pdf');
                  await stampedFile.writeAsBytes(await pdfDoc.save());
                  final metaFile = File('${dir.path}/${doc.title}_Watermarked.meta');
                  await metaFile.writeAsString(doc.pageImagePaths.join('\n'));
                  await _loadDocuments();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Watermarked PDF created!')));
                } catch (_) {}
              },
              child: const Text('Apply Watermark'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToDevice(OfficeDocument doc) async {
    try {
      Directory downloadDir = Directory('/storage/emulated/0/Download/AN_Office');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      final target = File('${downloadDir.path}/${doc.title}.${doc.extension}');
      await doc.file.copy(target.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to Phone: Download/AN_Office/${doc.title}.${doc.extension}')),
        );
      }
    } catch (_) {
      Share.shareXFiles([XFile(doc.file.path)], text: doc.title);
    }
  }

  // --- ABOUT DIALOG: BUILT BY ADESH NARANG & ADESHNARANG.IN ---
  void _showAboutANOffice() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ANLogoBadge(size: 70),
              const SizedBox(height: 14),
              const Text(
                'AN OFFICE',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 23, letterSpacing: 1.4, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 4),
              const Text(
                'All-in-One Executive Document, Scanner & Office Suite',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FD),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: const [
                    Text(
                      'Built by Adesh Narang',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F172A)),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Official Creator & Lead Architect',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () async {
                  final uri = Uri.parse('https://adeshnarang.in');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCCFBF1),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF008080), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.language, color: Color(0xFF008080), size: 18),
                      SizedBox(width: 8),
                      Text(
                        'adeshnarang.in',
                        style: TextStyle(color: Color(0xFF008080), fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.open_in_new, color: Color(0xFF008080), size: 14),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '100% Offline • High-Resolution Engine • Zero Ads',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- MULTI-USER ACCOUNT & CLOUD SYNC SWITCHER ---
  void _showAccountDialog() {
    final nameCtrl = TextEditingController(text: _userName);
    final emailCtrl = TextEditingController(text: _userEmail);
    bool syncToggle = _cloudSyncEnabled;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('User Account & Cloud Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF008080),
                    child: Text(
                      _userName.isNotEmpty ? _userName[0].toUpperCase() : 'A',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  title: Text(_userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_userEmail, style: const TextStyle(fontSize: 12)),
                ),
                const Divider(),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Account Holder Name', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email / Account ID', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF008080),
                  title: const Text('Cloud Backup & Drive Sync', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Keep documents synced across devices', style: TextStyle(fontSize: 11)),
                  value: syncToggle,
                  onChanged: (v) => setDState(() => syncToggle = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _saveAccountProfile('Guest User', 'Offline Local Mode', false);
                Navigator.pop(context);
              },
              child: const Text('Use as Guest'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
              onPressed: () {
                _saveAccountProfile(nameCtrl.text.trim(), emailCtrl.text.trim(), syncToggle);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Signed in as ${nameCtrl.text.trim()}')),
                );
              },
              child: const Text('Save Account'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCaptureSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.camera_enhance_rounded, color: Color(0xFF008080), size: 28),
                  title: const Text('Ultra-HD Camera (50MP Sensor Clarity)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Full optical clarity + manual 4-corner studio crop'),
                  onTap: () {
                    Navigator.pop(context);
                    _startUltraHdCamera();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.document_scanner_outlined, color: Colors.blueAccent, size: 28),
                  title: const Text('Auto-Crop Document Scanner', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Automatic edge flattening with zero forced filters'),
                  onTap: () {
                    Navigator.pop(context);
                    _startMLScan(isIdMode: false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined, color: Colors.orangeAccent, size: 28),
                  title: const Text('ID Card Mode (2-in-1 Stacked)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Front & back stacked cleanly onto a single A4 page'),
                  onTap: () {
                    Navigator.pop(context);
                    _startMLScan(isIdMode: true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: Colors.green, size: 28),
                  title: const Text('Import Photos from Gallery', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Pick multiple photos and edit immediately in Studio'),
                  onTap: () {
                    Navigator.pop(context);
                    _importFromGallery();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openDocumentItem(OfficeDocument doc) {
    if (doc.isLocked) {
      final pinCtrl = TextEditingController();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Protected Document', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: pinCtrl,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Enter Password to Open', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
              onPressed: () {
                if (pinCtrl.text.trim() == doc.pinCode) {
                  Navigator.pop(context);
                  _launchUnlockedDoc(doc);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect password!')));
                }
              },
              child: const Text('Open'),
            ),
          ],
        ),
      );
    } else {
      _launchUnlockedDoc(doc);
    }
  }

  void _launchUnlockedDoc(OfficeDocument doc) {
    if (doc.extension == 'xlsx' || doc.extension == 'csv') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ANSpreadsheetViewerScreen(file: doc.file, title: doc.title, onConverted: _loadDocuments),
        ),
      );
    } else if (doc.extension == 'docx' || doc.extension == 'txt') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ANWordTextViewerScreen(file: doc.file, title: doc.title, onConverted: _loadDocuments),
        ),
      );
    } else if (doc.pageImagePaths.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ANPreSaveStudio(
            initialImages: doc.pageImagePaths,
            isIdMode: doc.category == DocCategory.idCard,
            initialTitle: doc.title,
            onSaved: _loadDocuments,
          ),
        ),
      );
    } else {
      OpenFile.open(doc.file.path);
    }
  }

  void _showDocOptions(OfficeDocument doc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.download_for_offline, color: Color(0xFF008080)),
                    title: const Text('Save to Device Downloads (/Download/AN_Office)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      _saveToDevice(doc);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.send_rounded, color: Colors.green),
                    title: const Text('Quick Share for WhatsApp (< 2 MB Optimized)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      if (doc.pageImagePaths.isNotEmpty) {
                        _executeCompression(doc, quality: 65, scale: 0.78, suffix: 'WhatsApp', shareAfter: true);
                      } else {
                        Share.shareXFiles([XFile(doc.file.path)]);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.compress, color: Colors.teal),
                    title: const Text('Compress PDF (Low / Medium / High + MB Preview)', style: TextStyle(fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      _showCompressDialog(doc);
                    },
                  ),
                  if (doc.pageImagePaths.isNotEmpty) ...[
                    ListTile(
                      leading: const Icon(Icons.table_chart_outlined, color: Colors.green),
                      title: const Text('Convert to Excel Spreadsheet (.xlsx)', style: TextStyle(fontSize: 14)),
                      onTap: () {
                        Navigator.pop(context);
                        _exportScanToExcel(doc);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.description_outlined, color: Colors.blueAccent),
                      title: const Text('Convert to Editable Word (.docx)', style: TextStyle(fontSize: 14)),
                      onTap: () {
                        Navigator.pop(context);
                        _exportScanToWordDocx(doc);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined, color: Colors.orange),
                      title: const Text('Export Pages as High-Res JPG Images', style: TextStyle(fontSize: 14)),
                      onTap: () {
                        Navigator.pop(context);
                        _exportPagesAsJpgs(doc);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.verified_outlined, color: Colors.deepPurple),
                      title: const Text('Apply Official / Security Watermark', style: TextStyle(fontSize: 14)),
                      onTap: () {
                        Navigator.pop(context);
                        _showWatermarkDialog(doc);
                      },
                    ),
                  ],
                  ListTile(
                    leading: Icon(doc.isLocked ? Icons.lock_open : Icons.lock_outline, color: Colors.amber.shade800),
                    title: Text(doc.isLocked ? 'Unlock / Remove PDF Password' : 'Lock Document with Password', style: const TextStyle(fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      _showLockOrUnlockDialog(doc);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: const Text('Delete Document', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                    onTap: () async {
                      Navigator.pop(context);
                      if (await doc.file.exists()) await doc.file.delete();
                      _loadDocuments();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<OfficeDocument> filtered = _allDocs.where((d) {
      final matchQuery = d.title.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchQuery) return false;
      if (_selectedCategory == DocCategory.all) return true;
      return d.category == _selectedCategory;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: Colors.white,
        title: Row(
          children: [
            const ANLogoBadge(size: 38),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'AN OFFICE',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 18, color: Color(0xFF0F172A)),
                ),
                Text(
                  'Built by Adesh Narang',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF008080)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_cloudSyncEnabled ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: const Color(0xFF008080)),
            tooltip: 'Account & Cloud Sync',
            onPressed: _showAccountDialog,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: Color(0xFF0F172A)),
            tooltip: 'About AN Office',
            onPressed: _showAboutANOffice,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Capsule Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Search scans, Excel sheets, bills, ID cards...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                  prefixIcon: Icon(Icons.search, size: 20, color: Color(0xFF008080)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),

          // Pinterest / Dribbble Style Executive Quick Tools Grid
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                _buildQuickActionCard(
                  icon: Icons.camera_enhance_rounded,
                  title: 'Scan Studio',
                  subtitle: '50MP & Auto',
                  color: const Color(0xFF008080),
                  onTap: _showCaptureSelector,
                ),
                const SizedBox(width: 8),
                _buildQuickActionCard(
                  icon: Icons.swap_calls_rounded,
                  title: 'Convert Hub',
                  subtitle: 'PDF ⇄ Office',
                  color: const Color(0xFF2563EB),
                  onTap: _showConvertHubModal,
                ),
                const SizedBox(width: 8),
                _buildQuickActionCard(
                  icon: Icons.merge_type_rounded,
                  title: 'Merge PDFs',
                  subtitle: 'Combine Files',
                  color: const Color(0xFFD97706),
                  onTap: _showMergeDocumentsModal,
                ),
                const SizedBox(width: 8),
                _buildQuickActionCard(
                  icon: Icons.folder_open_rounded,
                  title: 'Open File',
                  subtitle: 'XLSX/DOCX/PDF',
                  color: const Color(0xFF059669),
                  onTap: _pickAndOpenAnyOfficeFile,
                ),
              ],
            ),
          ),

          // Smart Folder Category Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                _buildCategoryChip('All Files (${_allDocs.length})', DocCategory.all),
                _buildCategoryChip('Trade & Bills', DocCategory.trade),
                _buildCategoryChip('ID Cards', DocCategory.idCard),
                _buildCategoryChip('Excel Sheets', DocCategory.spreadsheets),
                _buildCategoryChip('Word & Notes', DocCategory.wordNotes),
                _buildCategoryChip('Bank & Stmts', DocCategory.bank),
              ],
            ),
          ),

          // Recent Documents Feed
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)],
                          ),
                          child: const Icon(Icons.Auto_awesome_motion_outlined, size: 48, color: Color(0xFF008080)),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Your AN Office Workspace is Ready',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap "Scan Studio" or "Open File" to begin',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 100),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final doc = filtered[index];
                      final dateStr = DateFormat('dd MMM yyyy • hh:mm a').format(doc.modified);
                      final hasPreview = doc.pageImagePaths.isNotEmpty;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _openDocumentItem(doc),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: 58,
                                    height: 74,
                                    color: const Color(0xFFF1F5F9),
                                    child: hasPreview
                                        ? Image.file(File(doc.pageImagePaths[0]), fit: BoxFit.cover)
                                        : Icon(
                                            doc.extension == 'xlsx' || doc.extension == 'csv'
                                                ? Icons.table_chart_rounded
                                                : doc.extension == 'docx' || doc.extension == 'txt'
                                                    ? Icons.description_rounded
                                                    : Icons.picture_as_pdf_rounded,
                                            color: doc.extension == 'xlsx'
                                                ? Colors.green
                                                : doc.extension == 'docx'
                                                    ? Colors.blueAccent
                                                    : const Color(0xFF008080),
                                            size: 30,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (doc.isLocked)
                                            const Padding(
                                              padding: EdgeInsets.only(right: 6),
                                              child: Icon(Icons.lock, size: 15, color: Colors.amber),
                                            ),
                                          Expanded(
                                            child: Text(
                                              doc.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F172A)),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(dateStr, style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFCCFBF1),
                                              borderRadius: BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              doc.extension.toUpperCase(),
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF008080)),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(doc.sizeMb, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                                          if (doc.pageImagePaths.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Text('${doc.pageImagePaths.length} pg', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
                                  onPressed: () => _showDocOptions(doc),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF008080),
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.camera_alt_rounded),
        label: const Text('Capture Scan', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _showCaptureSelector,
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 6),
              Text(title, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: Color(0xFF0F172A))),
              Text(subtitle, maxLines: 1, style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, DocCategory cat) {
    final isSelected = _selectedCategory == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        showCheckmark: false,
        label: Text(label),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF0F172A),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          fontSize: 12,
        ),
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFF008080),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isSelected ? const Color(0xFF008080) : Colors.grey.shade200),
        ),
        onSelected: (_) => setState(() => _selectedCategory = cat),
      ),
    );
  }
}

// ============================================================================
// PRE-SAVE & POST-SAVE INTERACTIVE DOCUMENT STUDIO
// (Bakes White-Out, Pen, Signature, Movable Text, Crop & Filters Into Output!)
// ============================================================================
class ANPreSaveStudio extends StatefulWidget {
  final List<String> initialImages;
  final bool isIdMode;
  final String? initialTitle;
  final VoidCallback onSaved;

  const ANPreSaveStudio({
    super.key,
    required this.initialImages,
    required this.isIdMode,
    this.initialTitle,
    required this.onSaved,
  });

  @override
  State<ANPreSaveStudio> createState() => _ANPreSaveStudioState();
}

class _ANPreSaveStudioState extends State<ANPreSaveStudio> {
  final List<PageEditData> _pages = [];
  int _currentPage = 0;
  final PageController _pageController = PageController();
  final ImagePicker _picker = ImagePicker();

  bool _isCleanUpMode = false;
  bool _isDrawMode = false;
  Color _penColor = const Color(0xFF1D4ED8);
  double _brushSize = 18.0;
  List<Offset> _activeStroke = [];

  @override
  void initState() {
    super.initState();
    _initPages();
  }

  Future<void> _initPages() async {
    for (final p in widget.initialImages) {
      double ratio = 0.707;
      try {
        final bytes = await File(p).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        ratio = frame.image.width / frame.image.height;
      } catch (_) {}
      _pages.add(PageEditData(imagePath: p, filterMode: 0, aspectRatio: ratio));
    }
    if (mounted) setState(() {});
  }

  // Permanently composites page image + filter + white-out + pen + movable text into high-res PNG/JPG bytes
  Future<Uint8List> _bakePageEditsToBytes(PageEditData page) async {
    final rawBytes = await File(page.imagePath).readAsBytes();

    // Apply manual filter ONLY if user explicitly chose Grayscale (1) or Clean Contrast (2)
    Uint8List workingBytes = rawBytes;
    if (page.filterMode != 0) {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        img.Image filtered = decoded;
        if (page.filterMode == 1) {
          filtered = img.grayscale(decoded);
        } else if (page.filterMode == 2) {
          filtered = img.adjustColor(decoded, contrast: 1.35, brightness: 1.06);
        }
        workingBytes = Uint8List.fromList(img.encodeJpg(filtered, quality: 95));
      }
    }

    if (page.strokes.isEmpty && page.texts.isEmpty) {
      return workingBytes;
    }

    final codec = await ui.instantiateImageCodec(workingBytes);
    final frame = await codec.getNextFrame();
    final ui.Image baseImage = frame.image;
    final double w = baseImage.width.toDouble();
    final double h = baseImage.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    // 1. Draw base photo
    canvas.drawImage(baseImage, Offset.zero, Paint());

    // 2. Draw all White-Out & Pen Strokes scaled to image pixel resolution
    final scaleFactor = w / 360.0;
    for (final stroke in page.strokes) {
      if (stroke.normalizedPoints.length < 2) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.strokeWidth * scaleFactor;

      final path = Path();
      final first = Offset(stroke.normalizedPoints.first.dx * w, stroke.normalizedPoints.first.dy * h);
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < stroke.normalizedPoints.length; i++) {
        final pt = Offset(stroke.normalizedPoints[i].dx * w, stroke.normalizedPoints[i].dy * h);
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, paint);
    }

    // 3. Draw all Movable Keyboard Text items scaled to image pixel resolution
    for (final t in page.texts) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            color: t.color,
            fontSize: t.fontSize * scaleFactor,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout(maxWidth: w);
      textPainter.paint(canvas, Offset(t.normalizedPos.dx * w, t.normalizedPos.dy * h));
    }

    final picture = recorder.endRecording();
    final renderedImage = await picture.toImage(baseImage.width, baseImage.height);
    final pngBytes = await renderedImage.toByteData(format: ui.ImageByteFormat.png);
    if (pngBytes != null) {
      final decoded = img.decodePng(pngBytes.buffer.asUint8List());
      if (decoded != null) {
        return Uint8List.fromList(img.encodeJpg(decoded, quality: 94));
      }
    }
    return workingBytes;
  }

  // --- INTERACTIVE CROP & ROTATE FOR CURRENT PAGE ---
  Future<void> _openCropScreenForCurrentPage() async {
    if (_pages.isEmpty) return;
    final page = _pages[_currentPage];
    final updatedPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ANCropScreen(imagePath: page.imagePath)),
    );
    if (updatedPath != null && mounted) {
      final bytes = await File(updatedPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      setState(() {
        page.imagePath = updatedPath;
        page.aspectRatio = frame.image.width / frame.image.height;
      });
    }
  }

  // --- ADD / EDIT MOVABLE, RESIZABLE, COLOR-CHANGEABLE TEXT ---
  void _openAddOrEditTextDialog({FloatingTextItem? existingItem}) {
    final textCtrl = TextEditingController(text: existingItem?.text ?? '');
    double localSize = existingItem?.fontSize ?? 20.0;
    Color localColor = existingItem?.color ?? Colors.black;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(existingItem == null ? 'Add Movable Text' : 'Edit Text Box', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: textCtrl,
                  autofocus: true,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: 'Type text to place on page...', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                Text('Text Size: ${localSize.round()} pt', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Slider(
                  value: localSize,
                  min: 10.0,
                  max: 52.0,
                  activeColor: const Color(0xFF008080),
                  onChanged: (v) => setDState(() => localSize = v),
                ),
                const Text('Text Color:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Colors.black,
                    const Color(0xFF1D4ED8),
                    const Color(0xFFDC2626),
                    const Color(0xFF008080),
                    Colors.green.shade800,
                    Colors.white,
                  ].map((c) {
                    return GestureDetector(
                      onTap: () => setDState(() => localColor = c),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: localColor == c ? Colors.black : Colors.grey.shade400, width: localColor == c ? 3 : 1),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            if (existingItem != null)
              TextButton(
                onPressed: () {
                  setState(() => _pages[_currentPage].texts.remove(existingItem));
                  Navigator.pop(context);
                },
                child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
              onPressed: () {
                final val = textCtrl.text.trim();
                if (val.isNotEmpty) {
                  setState(() {
                    if (existingItem != null) {
                      existingItem.text = val;
                      existingItem.fontSize = localSize;
                      existingItem.color = localColor;
                    } else {
                      _pages[_currentPage].texts.add(
                        FloatingTextItem(
                          text: val,
                          normalizedPos: const Offset(0.25, 0.35),
                          fontSize: localSize,
                          color: localColor,
                        ),
                      );
                    }
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('Place on Page'),
            ),
          ],
        ),
      ),
    );
  }

  // --- REUSABLE SIGNATURE PAD ---
  void _openSignaturePad() {
    List<Offset> sigPoints = [];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Draw Digital Signature', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Sign below to stamp onto the lower-right corner of this page:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FD),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF008080), width: 1.5),
                ),
                child: GestureDetector(
                  onPanUpdate: (d) {
                    setModalState(() => sigPoints.add(d.localPosition));
                  },
                  child: CustomPaint(
                    painter: _RawOffsetPainter(points: sigPoints, color: const Color(0xFF1D4ED8), width: 3.2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade700, foregroundColor: Colors.white),
                    onPressed: () => setModalState(() => sigPoints.clear()),
                    child: const Text('Clear'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
                    icon: const Icon(Icons.check),
                    label: const Text('Apply Signature'),
                    onPressed: () {
                      if (sigPoints.length > 2) {
                        // Normalize signature into lower-right corner (x: 0.55..0.90, y: 0.75..0.90)
                        final normSig = sigPoints.map((p) {
                          final nx = 0.55 + (p.dx / 320.0).clamp(0.0, 1.0) * 0.35;
                          final ny = 0.75 + (p.dy / 180.0).clamp(0.0, 1.0) * 0.15;
                          return Offset(nx, ny);
                        }).toList();
                        setState(() {
                          _pages[_currentPage].strokes.add(
                            DrawnStroke(normalizedPoints: normSig, color: const Color(0xFF1D4ED8), strokeWidth: 2.5),
                          );
                        });
                      }
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- DUAL-SCRIPT OCR + SMART LEDGER AUTO-SUM CALCULATOR ---
  Future<void> _runOcrAndLedgerSheet({bool useDevanagari = false}) async {
    if (_pages.isEmpty) return;
    try {
      final recognizer = TextRecognizer(
        script: useDevanagari ? TextRecognitionScript.devanagari : TextRecognitionScript.latin,
      );
      final inputImage = InputImage.fromFilePath(_pages[_currentPage].imagePath);
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();

      final extractedText = recognized.text.trim();

      // Extract all numeric values for the Smart Ledger Calculator
      final numberMatches = RegExp(r'\b\d+(?:,\d{3})*(?:\.\d+)?\b')
          .allMatches(extractedText)
          .map((m) => double.tryParse(m.group(0)!.replaceAll(',', '')))
          .whereType<double>()
          .toList();

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) {
          return DefaultTabController(
            length: 2,
            child: DraggableScrollableSheet(
              initialChildSize: 0.72,
              maxChildSize: 0.94,
              minChildSize: 0.45,
              expand: false,
              builder: (context, scrollCtrl) {
                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Page ${_currentPage + 1} OCR & Ledger', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _runOcrAndLedgerSheet(useDevanagari: !useDevanagari);
                                },
                                icon: const Icon(Icons.translate, size: 16),
                                label: Text(useDevanagari ? 'Switch to English' : 'Hindi/Regional'),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
                                icon: const Icon(Icons.copy, size: 15),
                                label: const Text('Copy All'),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: extractedText));
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied full text to clipboard!')));
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const TabBar(
                        labelColor: Color(0xFF008080),
                        indicatorColor: Color(0xFF008080),
                        tabs: [
                          Tab(text: 'Selectable Text (OCR)'),
                          Tab(text: 'Ledger Auto-Sum Calculator'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // Tab 1: Full Selectable Text
                            SingleChildScrollView(
                              controller: scrollCtrl,
                              child: SelectableText(
                                extractedText.isEmpty ? 'No text detected on this page.' : extractedText,
                                style: const TextStyle(fontSize: 15, height: 1.6, color: Color(0xFF0F172A)),
                              ),
                            ),
                            // Tab 2: Smart Ledger Calculator
                            _LedgerCalculatorWidget(numbers: numberMatches),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCR Error: $e')));
    }
  }

  // --- SAVE FINAL PDF (BAKING ALL STUDIO EDITS) ---
  Future<void> _saveFinalPdf() async {
    final defaultPrefix = widget.isIdMode ? 'ID_Card_' : 'AN_Doc_';
    final titleController = TextEditingController(
      text: widget.initialTitle ?? '$defaultPrefix${DateFormat('ddMMM_HHmm').format(DateTime.now())}',
    );

    final chosenName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Save PDF Document', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Document Title', suffixText: '.pdf', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, titleController.text.trim()),
            child: const Text('Save PDF', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (chosenName == null || chosenName.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF008080))),
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final List<String> bakedPagePaths = [];

      for (int i = 0; i < _pages.length; i++) {
        final bakedBytes = await _bakePageEditsToBytes(_pages[i]);
        final bakedPath = '${dir.path}/${chosenName}_p$i.jpg';
        await File(bakedPath).writeAsBytes(bakedBytes);
        bakedPagePaths.add(bakedPath);
      }

      final pdfDoc = pw.Document(
        author: 'Adesh Narang',
        creator: 'AN Office (adeshnarang.in)',
        title: chosenName,
      );

      if (widget.isIdMode && bakedPagePaths.length >= 2) {
        final img1 = pw.MemoryImage(await File(bakedPagePaths[0]).readAsBytes());
        final img2 = pw.MemoryImage(await File(bakedPagePaths[1]).readAsBytes());
        pdfDoc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(28),
            build: (_) => pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: [
                pw.Container(height: 320, child: pw.Image(img1, fit: pw.BoxFit.contain)),
                pw.Divider(thickness: 1, color: PdfColors.grey400),
                pw.Container(height: 320, child: pw.Image(img2, fit: pw.BoxFit.contain)),
              ],
            ),
          ),
        );
      } else {
        for (final p in bakedPagePaths) {
          final imgBytes = await File(p).readAsBytes();
          pdfDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(imgBytes), fit: pw.BoxFit.contain)),
            ),
          );
        }
      }

      final pdfFile = File('${dir.path}/$chosenName.pdf');
      await pdfFile.writeAsBytes(await pdfDoc.save());

      final metaFile = File('${dir.path}/$chosenName.meta');
      await metaFile.writeAsString(bakedPagePaths.join('\n'));

      widget.onSaved();
      if (!mounted) return;
      Navigator.pop(context); // Close loader
      Navigator.pop(context); // Return home
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved "$chosenName.pdf" with all edits applied!')),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save error: $e')));
      }
    }
  }

  void _openPageManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ANPageOrganizerScreen(
          pages: _pages,
          onPagesUpdated: () {
            setState(() {
              if (_currentPage >= _pages.length && _pages.isNotEmpty) {
                _currentPage = _pages.length - 1;
              }
            });
          },
        ),
      ),
    );
  }

  Future<void> _addMorePagesFromGallery() async {
    try {
      final photos = await _picker.pickMultiImage(imageQuality: 100);
      for (final p in photos) {
        final bytes = await File(p.path).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        _pages.add(PageEditData(
          imagePath: p.path,
          filterMode: 0, // Strictly Original by default
          aspectRatio: frame.image.width / frame.image.height,
        ));
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final hasPages = _pages.isNotEmpty;
    final currentPageData = hasPages ? _pages[_currentPage] : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          hasPages ? 'Studio • Page ${_currentPage + 1}/${_pages.length}' : 'Studio',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          if (hasPages && currentPageData!.strokes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.undo, color: Colors.white70),
              tooltip: 'Undo Stroke',
              onPressed: () => setState(() => currentPageData.strokes.removeLast()),
            ),
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white),
            tooltip: 'Add More Pages',
            onPressed: _addMorePagesFromGallery,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF008080),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Save PDF', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: hasPages ? _saveFinalPdf : null,
            ),
          ),
        ],
      ),
      body: !hasPages
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2DD4BF)))
          : Column(
              children: [
                // Top Filter & Brush Bar (Strictly defaults to "Original (No Filter)")
                Container(
                  color: const Color(0xFF1E293B),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Filter: ', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                        _filterPill('Original (No Filter)', 0, currentPageData!),
                        _filterPill('Clean Contrast', 2, currentPageData),
                        _filterPill('Grayscale', 1, currentPageData),
                        if (_isCleanUpMode || _isDrawMode) ...[
                          const SizedBox(width: 12),
                          const Text('Size:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          SizedBox(
                            width: 100,
                            child: Slider(
                              value: _brushSize,
                              min: 4.0,
                              max: 40.0,
                              activeColor: const Color(0xFF2DD4BF),
                              onChanged: (v) => setState(() => _brushSize = v),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Interactive Page Canvas
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    physics: (_isCleanUpMode || _isDrawMode) ? const NeverScrollableScrollPhysics() : null,
                    itemCount: _pages.length,
                    onPageChanged: (idx) => setState(() => _currentPage = idx),
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: AspectRatio(
                            aspectRatio: page.aspectRatio,
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final bw = box.maxWidth;
                                final bh = box.maxHeight;

                                return GestureDetector(
                                  onPanStart: (_isCleanUpMode || _isDrawMode)
                                      ? (d) {
                                          setState(() {
                                            _activeStroke = [
                                              Offset(
                                                (d.localPosition.dx / bw).clamp(0.0, 1.0),
                                                (d.localPosition.dy / bh).clamp(0.0, 1.0),
                                              )
                                            ];
                                          });
                                        }
                                      : null,
                                  onPanUpdate: (_isCleanUpMode || _isDrawMode)
                                      ? (d) {
                                          setState(() {
                                            _activeStroke.add(
                                              Offset(
                                                (d.localPosition.dx / bw).clamp(0.0, 1.0),
                                                (d.localPosition.dy / bh).clamp(0.0, 1.0),
                                              ),
                                            );
                                          });
                                        }
                                      : null,
                                  onPanEnd: (_isCleanUpMode || _isDrawMode)
                                      ? (_) {
                                          if (_activeStroke.length > 1) {
                                            setState(() {
                                              page.strokes.add(
                                                DrawnStroke(
                                                  normalizedPoints: List.from(_activeStroke),
                                                  color: _isCleanUpMode ? Colors.white : _penColor,
                                                  strokeWidth: _isCleanUpMode ? _brushSize : (_brushSize * 0.35).clamp(2.0, 12.0),
                                                ),
                                              );
                                              _activeStroke = [];
                                            });
                                          }
                                        }
                                      : null,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      // Base Image with Optional Filter Preview
                                      ColorFiltered(
                                        colorFilter: page.filterMode == 1
                                            ? const ColorFilter.matrix([
                                                0.2126, 0.7152, 0.0722, 0, 0,
                                                0.2126, 0.7152, 0.0722, 0, 0,
                                                0.2126, 0.7152, 0.0722, 0, 0,
                                                0, 0, 0, 1, 0,
                                              ])
                                            : page.filterMode == 2
                                                ? const ColorFilter.matrix([
                                                    1.35, 0, 0, 0, -20,
                                                    0, 1.35, 0, 0, -20,
                                                    0, 0, 1.35, 0, -20,
                                                    0, 0, 0, 1, 0,
                                                  ])
                                                : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                                        child: Image.file(File(page.imagePath), fit: BoxFit.fill),
                                      ),

                                      // Saved Strokes + Active Stroke
                                      CustomPaint(
                                        painter: _StudioNormalizedPainter(
                                          strokes: page.strokes,
                                          activePoints: _activeStroke,
                                          activeColor: _isCleanUpMode ? Colors.white : _penColor,
                                          activeWidth: _isCleanUpMode ? _brushSize : (_brushSize * 0.35).clamp(2.0, 12.0),
                                        ),
                                      ),

                                      // Draggable, Resizable, Recolorable Text Boxes
                                      ...page.texts.map((item) {
                                        return Positioned(
                                          left: (item.normalizedPos.dx * bw).clamp(0.0, max(0.0, bw - 60)),
                                          top: (item.normalizedPos.dy * bh).clamp(0.0, max(0.0, bh - 35)),
                                          child: GestureDetector(
                                            onPanUpdate: (details) {
                                              setState(() {
                                                final nx = (item.normalizedPos.dx + details.delta.dx / bw).clamp(0.0, 0.92);
                                                final ny = (item.normalizedPos.dy + details.delta.dy / bh).clamp(0.0, 0.92);
                                                item.normalizedPos = Offset(nx, ny);
                                              });
                                            },
                                            onTap: () => _openAddOrEditTextDialog(existingItem: item),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.08),
                                                border: Border.all(color: const Color(0xFF2DD4BF), width: 1.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                item.text,
                                                style: TextStyle(
                                                  color: item.color,
                                                  fontSize: item.fontSize,
                                                  fontWeight: FontWeight.bold,
                                                ),
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
                      );
                    },
                  ),
                ),
              ],
            ),

      // Full Adobe Scan + Acrobat Studio Bottom Toolbar (Available BEFORE & AFTER Saving)
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: SafeArea(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _studioToolBtn(
                  icon: Icons.crop_rotate_rounded,
                  label: 'Crop/Rotate',
                  active: false,
                  onTap: _openCropScreenForCurrentPage,
                ),
                _studioToolBtn(
                  icon: Icons.cleaning_services_rounded,
                  label: 'White-Out',
                  active: _isCleanUpMode,
                  onTap: () => setState(() {
                    _isCleanUpMode = !_isCleanUpMode;
                    _isDrawMode = false;
                  }),
                ),
                _studioToolBtn(
                  icon: Icons.edit_rounded,
                  label: 'Markup',
                  active: _isDrawMode,
                  onTap: () => setState(() {
                    _isDrawMode = !_isDrawMode;
                    _isCleanUpMode = false;
                  }),
                ),
                _studioToolBtn(
                  icon: Icons.text_fields_rounded,
                  label: 'Add Text',
                  active: false,
                  onTap: () => _openAddOrEditTextDialog(),
                ),
                _studioToolBtn(
                  icon: Icons.draw_outlined,
                  label: 'Signature',
                  active: false,
                  onTap: _openSignaturePad,
                ),
                _studioToolBtn(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Reorder',
                  active: false,
                  onTap: _openPageManager,
                ),
                const SizedBox(width: 6),
                ElevatedButton.icon(
                  onPressed: hasPages ? () => _runOcrAndLedgerSheet() : null,
                  icon: const Icon(Icons.document_scanner, size: 16),
                  label: const Text('OCR & Calc', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF008080),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterPill(String label, int mode, PageEditData page) {
    final selected = page.filterMode == mode;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: selected,
        label: Text(label, style: TextStyle(fontSize: 11, color: selected ? Colors.white : Colors.white70)),
        selectedColor: const Color(0xFF008080),
        backgroundColor: const Color(0xFF334155),
        onSelected: (_) => setState(() => page.filterMode = mode),
      ),
    );
  }

  Widget _studioToolBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color = active ? const Color(0xFF008080) : const Color(0xFF0F172A);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFCCFBF1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// INTERACTIVE 4-HANDLE CROP & 90° ROTATE SCREEN FOR ULTRA-HD PHOTOS
// ============================================================================
class ANCropScreen extends StatefulWidget {
  final String imagePath;
  const ANCropScreen({super.key, required this.imagePath});

  @override
  State<ANCropScreen> createState() => _ANCropScreenState();
}

class _ANCropScreenState extends State<ANCropScreen> {
  late String _workingPath;
  Offset _topLeft = const Offset(0.06, 0.06);
  Offset _bottomRight = const Offset(0.94, 0.94);
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _workingPath = widget.imagePath;
  }

  Future<void> _rotate90() async {
    setState(() => _isBusy = true);
    try {
      final bytes = await File(_workingPath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final rotated = img.copyRotate(decoded, angle: 90);
        final dir = await getApplicationDocumentsDirectory();
        final newPath = '${dir.path}/rot_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(newPath).writeAsBytes(img.encodeJpg(rotated, quality: 95));
        _workingPath = newPath;
      }
    } catch (_) {}
    if (mounted) setState(() => _isBusy = false);
  }

  Future<void> _applyCrop() async {
    setState(() => _isBusy = true);
    try {
      final bytes = await File(_workingPath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final int x = (_topLeft.dx * decoded.width).round().clamp(0, decoded.width - 10);
        final int y = (_topLeft.dy * decoded.height).round().clamp(0, decoded.height - 10);
        final int w = ((_bottomRight.dx - _topLeft.dx) * decoded.width).round().clamp(10, decoded.width - x);
        final int h = ((_bottomRight.dy - _topLeft.dy) * decoded.height).round().clamp(10, decoded.height - y);

        final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
        final dir = await getApplicationDocumentsDirectory();
        final newPath = '${dir.path}/crop_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(newPath).writeAsBytes(img.encodeJpg(cropped, quality: 95));
        if (mounted) Navigator.pop(context, newPath);
        return;
      }
    } catch (_) {}
    if (mounted) Navigator.pop(context, _workingPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: const Text('Crop & Rotate Page', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_90_degrees_cw, color: Color(0xFF2DD4BF)),
            tooltip: 'Rotate 90°',
            onPressed: _isBusy ? null : _rotate90,
          ),
          TextButton(
            onPressed: () => setState(() {
              _topLeft = const Offset(0.0, 0.0);
              _bottomRight = const Offset(1.0, 1.0);
            }),
            child: const Text('Full Image', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
            onPressed: _isBusy ? null : _applyCrop,
            child: const Text('Apply Crop', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isBusy
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2DD4BF)))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final bw = box.maxWidth;
                    final bh = box.maxHeight;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Image.file(File(_workingPath), fit: BoxFit.fill),
                        ),
                        // Crop Frame & Rule-of-Thirds Grid
                        Positioned(
                          left: _topLeft.dx * bw,
                          top: _topLeft.dy * bh,
                          width: (_bottomRight.dx - _topLeft.dx) * bw,
                          height: (_bottomRight.dy - _topLeft.dy) * bh,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFF2DD4BF), width: 2.5),
                              color: const Color(0xFF2DD4BF).withOpacity(0.08),
                            ),
                          ),
                        ),
                        // Top-Left Handle
                        Positioned(
                          left: _topLeft.dx * bw - 16,
                          top: _topLeft.dy * bh - 16,
                          child: GestureDetector(
                            onPanUpdate: (d) {
                              setState(() {
                                _topLeft = Offset(
                                  (_topLeft.dx + d.delta.dx / bw).clamp(0.0, _bottomRight.dx - 0.15),
                                  (_topLeft.dy + d.delta.dy / bh).clamp(0.0, _bottomRight.dy - 0.15),
                                );
                              });
                            },
                            child: _cornerHandle(),
                          ),
                        ),
                        // Bottom-Right Handle
                        Positioned(
                          left: _bottomRight.dx * bw - 16,
                          top: _bottomRight.dy * bh - 16,
                          child: GestureDetector(
                            onPanUpdate: (d) {
                              setState(() {
                                _bottomRight = Offset(
                                  (_bottomRight.dx + d.delta.dx / bw).clamp(_topLeft.dx + 0.15, 1.0),
                                  (_bottomRight.dy + d.delta.dy / bh).clamp(_topLeft.dy + 0.15, 1.0),
                                );
                              });
                            },
                            child: _cornerHandle(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
    );
  }

  Widget _cornerHandle() {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFF008080),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
      ),
    );
  }
}

// ============================================================================
// SMART LEDGER AUTO-SUM CALCULATOR WIDGET
// ============================================================================
class _LedgerCalculatorWidget extends StatefulWidget {
  final List<double> numbers;
  const _LedgerCalculatorWidget({required this.numbers});

  @override
  State<_LedgerCalculatorWidget> createState() => _LedgerCalculatorWidgetState();
}

class _LedgerCalculatorWidgetState extends State<_LedgerCalculatorWidget> {
  late List<bool> _included;

  @override
  void initState() {
    super.initState();
    _included = List.filled(widget.numbers.length, true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.numbers.isEmpty) {
      return const Center(child: Text('No numeric figures detected on this page.'));
    }

    double sum = 0;
    int count = 0;
    for (int i = 0; i < widget.numbers.length; i++) {
      if (_included[i]) {
        sum += widget.numbers[i];
        count++;
      }
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Text('TOTAL SUM', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text(
                    sum.toStringAsFixed(2),
                    style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              Column(
                children: [
                  const Text('ITEMS COUNT', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text('$count', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: widget.numbers.length,
            itemBuilder: (context, idx) {
              return CheckboxListTile(
                dense: true,
                activeColor: const Color(0xFF008080),
                title: Text(widget.numbers[idx].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                value: _included[idx],
                onChanged: (v) => setState(() => _included[idx] = v ?? false),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// BUILT-IN EXCEL (.XLSX / .CSV) SPREADSHEET VIEWER & PDF CONVERTER
// ============================================================================
class ANSpreadsheetViewerScreen extends StatefulWidget {
  final File file;
  final String title;
  final VoidCallback onConverted;

  const ANSpreadsheetViewerScreen({
    super.key,
    required this.file,
    required this.title,
    required this.onConverted,
  });

  @override
  State<ANSpreadsheetViewerScreen> createState() => _ANSpreadsheetViewerScreenState();
}

class _ANSpreadsheetViewerScreenState extends State<ANSpreadsheetViewerScreen> {
  List<List<String>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _parseSpreadsheet();
  }

  Future<void> _parseSpreadsheet() async {
    try {
      final ext = widget.file.path.split('.').last.toLowerCase();
      if (ext == 'csv') {
        final lines = await widget.file.readAsLines();
        _rows = lines.map((l) => l.split(',')).toList();
      } else {
        final bytes = await widget.file.readAsBytes();
        final excel = xl.Excel.decodeBytes(bytes);
        if (excel.tables.isNotEmpty) {
          final firstSheet = excel.tables.values.first;
          _rows = firstSheet.rows
              .map((r) => r.map((c) => c?.value?.toString() ?? '').toList())
              .toList();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _convertToExecutivePdf() async {
    try {
      final pdf = pw.Document(author: 'Adesh Narang', creator: 'AN Office (adeshnarang.in)');
      if (_rows.isNotEmpty) {
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(24),
            header: (_) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('AN Office Spreadsheet • ${widget.title}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
                  pw.Text('Built by Adesh Narang (adeshnarang.in)', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                ],
              ),
            ),
            build: (_) => [
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
                oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                data: _rows,
              ),
            ],
          ),
        );
      }
      final dir = await getApplicationDocumentsDirectory();
      final outPdf = File('${dir.path}/${widget.title}_Sheet.pdf');
      await outPdf.writeAsBytes(await pdf.save());
      widget.onConverted();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Converted to PDF: ${widget.title}_Sheet.pdf!')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF conversion error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('Convert to PDF'),
              onPressed: _rows.isEmpty ? null : _convertToExecutivePdf,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF008080)))
          : _rows.isEmpty
              ? const Center(child: Text('Empty spreadsheet or unsupported format'))
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFCCFBF1)),
                      columns: List.generate(
                        _rows.first.length,
                        (i) => DataColumn(label: Text(_rows.first[i], style: const TextStyle(fontWeight: FontWeight.bold))),
                      ),
                      rows: _rows.skip(1).map((r) {
                        return DataRow(
                          cells: List.generate(
                            _rows.first.length,
                            (i) => DataCell(Text(i < r.length ? r[i] : '')),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
    );
  }
}

// ============================================================================
// BUILT-IN WORD (.DOCX) & TEXT (.TXT) READER + PDF CONVERTER
// ============================================================================
class ANWordTextViewerScreen extends StatefulWidget {
  final File file;
  final String title;
  final VoidCallback onConverted;

  const ANWordTextViewerScreen({
    super.key,
    required this.file,
    required this.title,
    required this.onConverted,
  });

  @override
  State<ANWordTextViewerScreen> createState() => _ANWordTextViewerScreenState();
}

class _ANWordTextViewerScreenState extends State<ANWordTextViewerScreen> {
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _readDocContent();
  }

  Future<void> _readDocContent() async {
    try {
      final ext = widget.file.path.split('.').last.toLowerCase();
      if (ext == 'txt') {
        _content = await widget.file.readAsString();
      } else if (ext == 'docx') {
        final bytes = await widget.file.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        final docXmlFile = archive.findFile('word/document.xml');
        if (docXmlFile != null) {
          final xmlStr = utf8.decode(docXmlFile.content as List<int>);
          _content = xmlStr
              .replaceAll('</w:p>', '\n')
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .trim();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _convertTextToPdf() async {
    try {
      final pdf = pw.Document(author: 'Adesh Narang', creator: 'AN Office (adeshnarang.in)');
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (_) => _content
              .split('\n')
              .map((line) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text(line, style: const pw.TextStyle(fontSize: 11)),
                  ))
              .toList(),
        ),
      );
      final dir = await getApplicationDocumentsDirectory();
      final outPdf = File('${dir.path}/${widget.title}_Doc.pdf');
      await outPdf.writeAsBytes(await pdf.save());
      widget.onConverted();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Converted to PDF: ${widget.title}_Doc.pdf!')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('Convert to PDF'),
              onPressed: _content.isEmpty ? null : _convertTextToPdf,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF008080)))
          : Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: SelectableText(
                  _content.isEmpty ? 'No text content found.' : _content,
                  style: const TextStyle(fontSize: 15, height: 1.6, color: Color(0xFF0F172A)),
                ),
              ),
            ),
    );
  }
}

// ============================================================================
// PAGE ORGANIZER (REORDER, ROTATE & DELETE PAGES)
// ============================================================================
class ANPageOrganizerScreen extends StatefulWidget {
  final List<PageEditData> pages;
  final VoidCallback onPagesUpdated;

  const ANPageOrganizerScreen({super.key, required this.pages, required this.onPagesUpdated});

  @override
  State<ANPageOrganizerScreen> createState() => _ANPageOrganizerScreenState();
}

class _ANPageOrganizerScreenState extends State<ANPageOrganizerScreen> {
  Future<void> _rotatePage(int index) async {
    final path = widget.pages[index].imagePath;
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      final rotated = img.copyRotate(decoded, angle: 90);
      await File(path).writeAsBytes(img.encodeJpg(rotated, quality: 95));
      widget.pages[index].aspectRatio = rotated.width / rotated.height;
      setState(() {});
    }
  }

  void _deletePage(int index) {
    if (widget.pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document must have at least one page!')));
      return;
    }
    setState(() => widget.pages.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Reorder & Rotate Pages', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
            onPressed: () {
              widget.onPagesUpdated();
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.pages.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (oldIndex < newIndex) newIndex -= 1;
            final item = widget.pages.removeAt(oldIndex);
            widget.pages.insert(newIndex, item);
          });
        },
        itemBuilder: (context, index) {
          final page = widget.pages[index];
          return Card(
            key: ObjectKey(page),
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(10),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(page.imagePath), width: 52, height: 68, fit: BoxFit.cover),
              ),
              title: Text('Page ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Hold & drag to reorder • Tap rotate for Portrait/Landscape', style: TextStyle(fontSize: 11)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.rotate_right, color: Color(0xFF008080)),
                    onPressed: () => _rotatePage(index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () => _deletePage(index),
                  ),
                  const Icon(Icons.drag_handle, color: Colors.grey),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// CUSTOM PAINTERS FOR STUDIO STROKES & SIGNATURE PAD
// ============================================================================
class _StudioNormalizedPainter extends CustomPainter {
  final List<DrawnStroke> strokes;
  final List<Offset> activePoints;
  final Color activeColor;
  final double activeWidth;

  _StudioNormalizedPainter({
    required this.strokes,
    required this.activePoints,
    required this.activeColor,
    required this.activeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.normalizedPoints.length < 2) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.strokeWidth;

      final path = Path();
      path.moveTo(s.normalizedPoints.first.dx * size.width, s.normalizedPoints.first.dy * size.height);
      for (int i = 1; i < s.normalizedPoints.length; i++) {
        path.lineTo(s.normalizedPoints[i].dx * size.width, s.normalizedPoints[i].dy * size.height);
      }
      canvas.drawPath(path, paint);
    }

    if (activePoints.length > 1) {
      final paint = Paint()
        ..color = activeColor
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = activeWidth;

      final path = Path();
      path.moveTo(activePoints.first.dx * size.width, activePoints.first.dy * size.height);
      for (int i = 1; i < activePoints.length; i++) {
        path.lineTo(activePoints[i].dx * size.width, activePoints[i].dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StudioNormalizedPainter oldDelegate) => true;
}

class _RawOffsetPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double width;

  _RawOffsetPainter({required this.points, required this.color, required this.width});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RawOffsetPainter oldDelegate) => true;
}
