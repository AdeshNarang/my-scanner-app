import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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

void main() async {
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
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          primary: const Color(0xFF0F172A),
          secondary: const Color(0xFFB45309),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const ExecutiveMasterShell(),
    );
  }
}

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

class EditablePageItem {
  String imagePath;
  int quarterTurns;
  String filterMode;
  String overlayText;
  Offset overlayPosition;

  EditablePageItem({
    required this.imagePath,
    this.quarterTurns = 0,
    this.filterMode = 'original',
    this.overlayText = '',
    this.overlayPosition = const Offset(40, 40),
  });
}

class ExecutiveMasterShell extends StatefulWidget {
  const ExecutiveMasterShell({super.key});

  @override
  State<ExecutiveMasterShell> createState() => _ExecutiveMasterShellState();
}

class _ExecutiveMasterShellState extends State<ExecutiveMasterShell> {
  int _tabIndex = 0;
  List<VaultFile> _vaultFiles = [];
  Set<String> _lockedFileNames = {};
  String _searchQuery = '';
  String _selectedCategory = 'ALL';

  List<String> _accounts = ['Adesh Narang (Admin)', 'Head Office Desk', 'Accounts & Ledger'];
  String _currentAccount = 'Adesh Narang (Admin)';
  String? _masterPin;
  bool _isVaultUnlocked = false;
  bool _autoCloudSync = true;
  int _defaultCompression = 75;

  @override
  void initState() {
    super.initState();
    _initWorkspace();
  }

  Future<void> _initWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _accounts = prefs.getStringList('user_accounts') ??
          ['Adesh Narang (Admin)', 'Head Office Desk', 'Accounts & Ledger'];
      _currentAccount = prefs.getString('active_account') ?? _accounts.first;
      _masterPin = prefs.getString('master_pin');
      _autoCloudSync = prefs.getBool('auto_cloud_sync') ?? true;
      _defaultCompression = prefs.getInt('default_compression') ?? 75;
      _lockedFileNames = (prefs.getStringList('locked_files') ?? []).toSet();
      _isVaultUnlocked = (_masterPin == null || _masterPin!.isEmpty);
    });
    await _reloadVault();
  }

  Future<Directory> _getAccountVaultDir() async {
    final base = await getApplicationDocumentsDirectory();
    final safeFolder = _currentAccount.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final dir = Directory(p.join(base.path, 'AN_Office_Vault', safeFolder));
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
        if (['PDF', 'DOCX', 'XLSX', 'CSV', 'TXT', 'PNG', 'JPG'].contains(ext)) {
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

  Future<void> _toggleFileLock(VaultFile file) async {
    final prefs = await SharedPreferences.getInstance();
    if (_lockedFileNames.contains(file.name)) {
      final verified = await _verifyPinDialog('Enter PIN to Unlock ${file.name}');
      if (!verified) return;
      _lockedFileNames.remove(file.name);
    } else {
      if (_masterPin == null || _masterPin!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Set a Master PIN in Accounts tab first!')),
        );
        return;
      }
      _lockedFileNames.add(file.name);
    }
    await prefs.setStringList('locked_files', _lockedFileNames.toList());
    await _reloadVault();
  }

  Future<bool> _verifyPinDialog(String title) async {
    if (_masterPin == null || _masterPin!.isEmpty) return true;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(
            labelText: '4-Digit Security PIN',
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
    if (ok != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid Security PIN! Access Denied.')),
      );
    }
    return ok == true;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _launchScannerStudio({bool fromGallery = false}) async {
    List<String> paths = [];
    final picker = ImagePicker();

    if (!fromGallery) {
      final cam = await picker.pickImage(source: ImageSource.camera);
      if (cam != null) paths.add(cam.path);
    } else {
      final picked = await picker.pickMultiImage();
      paths.addAll(picked.map((x) => x.path));
    }

    if (paths.isEmpty || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InteractiveScanStudio(
          initialPaths: paths,
          defaultCompression: _defaultCompression,
          onSavePdf: (bytes, name, lockPdf) async {
            final dir = await _getAccountVaultDir();
            final clean = name.endsWith('.pdf') ? name : '$name.pdf';
            final file = File(p.join(dir.path, clean));
            await file.writeAsBytes(bytes);
            if (lockPdf) {
              _lockedFileNames.add(clean);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setStringList('locked_files', _lockedFileNames.toList());
            }
            await _reloadVault();
          },
        ),
      ),
    );
  }

  Future<void> _launchBilingualOcr() async {
    TextRecognitionScript chosenScript = TextRecognitionScript.latin;
    ImageSource chosenSource = ImageSource.gallery;

    final proceed = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Offline AI OCR Text & Word Extractor',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('Select Script Language:'),
              const SizedBox(height: 8),
              SegmentedButton<TextRecognitionScript>(
                segments: const [
                  ButtonSegment(
                    value: TextRecognitionScript.latin,
                    label: Text('English / Latin'),
                    icon: Icon(Icons.abc),
                  ),
                  ButtonSegment(
                    value: TextRecognitionScript.devanagiri,
                    label: Text('Hindi / देवनागरी'),
                    icon: Icon(Icons.translate),
                  ),
                ],
                selected: {chosenScript},
                onSelectionChanged: (s) => setModalState(() => chosenScript = s.first),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        chosenSource = ImageSource.camera;
                        Navigator.pop(ctx, true);
                      },
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        chosenSource = ImageSource.gallery;
                        Navigator.pop(ctx, true);
                      },
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery Image'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (proceed != true) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: chosenSource);
    if (picked == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Running Offline ML Kit OCR Engine...')),
          ],
        ),
      ),
    );

    String extracted = '';
    try {
      final input = InputImage.fromFilePath(picked.path);
      final recognizer = TextRecognizer(script: chosenScript);
      final result = await recognizer.processImage(input);
      extracted = result.text;
      await recognizer.close();
    } catch (e) {
      extracted = 'OCR Error: $e';
    }

    if (!mounted) return;
    Navigator.pop(context);

    _openWordStudio(
      initialName: 'OCR_${DateFormat('ddMMM_HHmm').format(DateTime.now())}',
      initialText: extracted.isEmpty ? 'No text detected.' : extracted,
    );
  }

  Future<void> _launchImageToExcelConverter() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Scanning Bill / Table into Excel Grid...')),
          ],
        ),
      ),
    );

    List<Map<String, String>> parsedRows = [];
    try {
      final input = InputImage.fromFilePath(picked.path);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final res = await recognizer.processImage(input);
      await recognizer.close();

      final lines = res.text.split('\n').where((l) => l.trim().isNotEmpty).toList();
      for (final line in lines) {
        final numMatches = RegExp(r'\d+(\.\d+)?').allMatches(line).map((m) => m.group(0)!).toList();
        final textPart = line.replaceAll(RegExp(r'[\d\.\,\₹\$]+'), '').trim();
        parsedRows.add({
          'item': textPart.isEmpty ? line : textPart,
          'qty': numMatches.length >= 2 ? numMatches[0] : '1',
          'rate': numMatches.isNotEmpty ? numMatches.last : '0',
        });
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.pop(context);

    _openExcelStudio(prefilledRows: parsedRows);
  }

  void _openExcelStudio({List<Map<String, String>>? prefilledRows, String? existingFilePath}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExcelSpreadsheetStudio(
          prefilledRows: prefilledRows,
          existingFilePath: existingFilePath,
          onSaveFile: (bytes, fileNameWithExt) async {
            final dir = await _getAccountVaultDir();
            final file = File(p.join(dir.path, fileNameWithExt));
            await file.writeAsBytes(bytes);
            await _reloadVault();
          },
        ),
      ),
    );
  }

  void _openWordStudio({String initialName = '', String initialText = ''}) {
    final nameCtrl = TextEditingController(
      text: initialName.isEmpty
          ? 'Word_${DateFormat('ddMMM_HHmm').format(DateTime.now())}'
          : initialName,
    );
    final bodyCtrl = TextEditingController(text: initialText);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('Word (.DOCX) & PDF Writer'),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.save_outlined),
                tooltip: 'Export Document',
                onSelected: (fmt) async {
                  final dir = await _getAccountVaultDir();
                  final base = nameCtrl.text.trim().isEmpty ? 'Document' : nameCtrl.text.trim();

                  if (fmt == 'DOCX') {
                    final bytes = _createOpenXmlDocx(bodyCtrl.text);
                    await File(p.join(dir.path, '$base.docx')).writeAsBytes(bytes);
                  } else if (fmt == 'PDF') {
                    final pdf = pw.Document();
                    pdf.addPage(
                      pw.MultiPage(
                        pageFormat: PdfPageFormat.a4,
                        build: (_) => [
                          pw.Header(level: 0, text: base),
                          pw.Paragraph(text: bodyCtrl.text),
                        ],
                      ),
                    );
                    await File(p.join(dir.path, '$base.pdf')).writeAsBytes(await pdf.save());
                  } else {
                    await File(p.join(dir.path, '$base.txt')).writeAsString(bodyCtrl.text);
                  }
                  await _reloadVault();
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Exported $base.$fmt to Vault!')),
                    );
                    Navigator.pop(ctx);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'DOCX', child: Text('Save as Word (.docx)')),
                  PopupMenuItem(value: 'PDF', child: Text('Convert & Save as PDF (.pdf)')),
                  PopupMenuItem(value: 'TXT', child: Text('Save as Plain Text (.txt)')),
                ],
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Document Title',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.article_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: bodyCtrl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      labelText: 'Type or paste document body here...',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Uint8List _createOpenXmlDocx(String text) {
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

    final paragraphs = text.split('\n').map((line) {
      final escaped = const HtmlEscape().convert(line);
      return '<w:p><w:r><w:t>$escaped</w:t></w:r></w:p>';
    }).join();

    final docXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>$paragraphs</w:body>
</w:document>''';

    final ctBytes = utf8.encode(contentTypes);
    final relsBytes = utf8.encode(rels);
    final docBytes = utf8.encode(docXml);

    archive.addFile(ArchiveFile('[Content_Types].xml', ctBytes.length, ctBytes));
    archive.addFile(ArchiveFile('_rels/.rels', relsBytes.length, relsBytes));
    archive.addFile(ArchiveFile('word/document.xml', docBytes.length, docBytes));

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  static String _extractTextFromDocx(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (file.name == 'word/document.xml') {
          final xmlStr = utf8.decode(file.content as List<int>);
          final matches = RegExp(r'<w:t[^>]*>(.*?)</w:t>').allMatches(xmlStr);
          return matches.map((m) => m.group(1) ?? '').join(' ');
        }
      }
    } catch (_) {}
    return 'Unable to parse .docx content.';
  }

  Future<void> _openPdfMergerDialog() async {
    final pdfDocs = _vaultFiles.where((f) => f.ext == 'PDF').toList();
    if (pdfDocs.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need at least 2 PDF files in Vault to merge!')),
      );
      return;
    }

    final Set<String> selectedPaths = {};
    final nameCtrl = TextEditingController(
      text: 'Merged_${DateFormat('ddMMM_HHmm').format(DateTime.now())}',
    );

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Merge Multiple PDFs'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Merged Output PDF Name'),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: pdfDocs.length,
                    itemBuilder: (_, i) {
                      final d = pdfDocs[i];
                      final checked = selectedPaths.contains(d.path);
                      return CheckboxListTile(
                        value: checked,
                        title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onChanged: (v) {
                          setModalState(() {
                            if (v == true) {
                              selectedPaths.add(d.path);
                            } else {
                              selectedPaths.remove(d.path);
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
            FilledButton(
              onPressed: selectedPaths.length < 2
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      final combinedPdf = pw.Document();
                      for (final path in selectedPaths) {
                        final rawBytes = await File(path).readAsBytes();
                        await for (final page in Printing.raster(rawBytes, dpi: 150)) {
                          final png = await page.toPng();
                          final img = pw.MemoryImage(png);
                          combinedPdf.addPage(
                            pw.Page(
                              pageFormat: PdfPageFormat.a4,
                              build: (_) => pw.Center(child: pw.Image(img)),
                            ),
                          );
                        }
                      }
                      final dir = await _getAccountVaultDir();
                      final outFile = File(p.join(dir.path, '${nameCtrl.text.trim()}.pdf'));
                      await outFile.writeAsBytes(await combinedPdf.save());
                      await _reloadVault();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Merged PDF Created in Vault!')),
                        );
                      }
                    },
              child: const Text('Merge PDFs'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInAppViewer(VaultFile file) async {
    if (file.isLocked) {
      final ok = await _verifyPinDialog('Unlock ${file.name}');
      if (!ok) return;
    }

    if (!mounted) return;

    if (file.ext == 'PDF') {
      final bytes = await File(file.path).readAsBytes();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(file.name),
              actions: [
                IconButton(
                  tooltip: 'Convert PDF to Editable Word (.DOCX)',
                  icon: const Icon(Icons.transform),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _convertPdfToWord(file);
                  },
                ),
              ],
            ),
            body: PdfPreview(
              build: (_) async => bytes,
              canChangeOrientation: true,
              canChangePageFormat: false,
            ),
          ),
        ),
      );
    } else if (file.ext == 'DOCX') {
      final bytes = await File(file.path).readAsBytes();
      final text = _extractTextFromDocx(bytes);
      _openWordStudio(
        initialName: p.basenameWithoutExtension(file.name),
        initialText: text,
      );
    } else if (file.ext == 'TXT' || file.ext == 'CSV') {
      final text = await File(file.path).readAsString();
      _openWordStudio(
        initialName: p.basenameWithoutExtension(file.name),
        initialText: text,
      );
    } else if (file.ext == 'XLSX') {
      _openExcelStudio(existingFilePath: file.path);
    } else {
      await OpenFilex.open(file.path);
    }
  }

  Future<void> _convertPdfToWord(VaultFile pdfFile) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Converting PDF Pages to Word (.docx) via OCR...')),
          ],
        ),
      ),
    );

    final StringBuffer extractedBuffer = StringBuffer();
    try {
      final rawBytes = await File(pdfFile.path).readAsBytes();
      final tempDir = await getTemporaryDirectory();
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      int pageNum = 1;

      await for (final page in Printing.raster(rawBytes, dpi: 150)) {
        final png = await page.toPng();
        final tempImg = File(p.join(tempDir.path, 'pdf_p_$pageNum.png'));
        await tempImg.writeAsBytes(png);
        final res = await recognizer.processImage(InputImage.fromFilePath(tempImg.path));
        extractedBuffer.writeln('--- Page $pageNum ---');
        extractedBuffer.writeln(res.text);
        extractedBuffer.writeln();
        pageNum++;
      }
      await recognizer.close();
    } catch (e) {
      extractedBuffer.writeln('Conversion note: $e');
    }

    if (!mounted) return;
    Navigator.pop(context);

    _openWordStudio(
      initialName: '${p.basenameWithoutExtension(pdfFile.name)}_Converted',
      initialText: extractedBuffer.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVaultUnlocked) {
      final pinCtrl = TextEditingController();
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 56, color: Color(0xFF0F172A)),
                    const SizedBox(height: 12),
                    const Text(
                      'AN OFFICE SECURITY VAULT',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Active Account: $_currentAccount',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: 'Enter 4-Digit Master PIN',
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
                              const SnackBar(content: Text('Incorrect Master PIN!')),
                            );
                          }
                        },
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Unlock Executive Suite'),
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AN OFFICE',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 19),
            ),
            Text(
              '$_currentAccount • adeshnarang.in',
              style: const TextStyle(fontSize: 11, color: Color(0xFFD4AF37)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Switch User Account',
            icon: const Icon(Icons.switch_account_outlined),
            onPressed: _showAccountSwitcher,
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
          _buildExecutiveStudioTab(),
          _buildUniversalVaultTab(),
          _buildSettingsAndAccountsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: const Color(0xFFD4AF37),
        onPressed: () => _launchScannerStudio(fromGallery: false),
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Capture Page', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_customize_outlined), label: 'Studio'),
          NavigationDestination(icon: Icon(Icons.folder_special_outlined), label: 'File Vault'),
          NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: 'Accounts'),
        ],
      ),
    );
  }

  Widget _buildExecutiveStudioTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
                ),
                child: const Text(
                  'AN',
                  style: TextStyle(
                    color: Color(0xFFD4AF37),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AN Office Productivity Suite',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_vaultFiles.length} Vault Docs • ${_autoCloudSync ? "Cloud Backup Ready" : "100% Offline"}',
                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'ALL OFFICE & SCANNER TOOLS',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF475569)),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            _studioToolTile(
              icon: Icons.camera_enhance_rounded,
              title: 'Camera Capture',
              sub: 'Capture & Build PDF',
              color: const Color(0xFF0F172A),
              onTap: () => _launchScannerStudio(fromGallery: false),
            ),
            _studioToolTile(
              icon: Icons.collections_outlined,
              title: 'Gallery to PDF',
              sub: 'Batch Import & Compress',
              color: const Color(0xFF1D4ED8),
              onTap: () => _launchScannerStudio(fromGallery: true),
            ),
            _studioToolTile(
              icon: Icons.translate_rounded,
              title: 'Hindi/Eng OCR',
              sub: 'Devanagari & Latin to Word',
              color: const Color(0xFF047857),
              onTap: _launchBilingualOcr,
            ),
            _studioToolTile(
              icon: Icons.grid_on_rounded,
              title: 'Image to Excel',
              sub: 'Scan Bill/Table to .XLSX',
              color: const Color(0xFF15803D),
              onTap: _launchImageToExcelConverter,
            ),
            _studioToolTile(
              icon: Icons.table_view_rounded,
              title: 'Excel Ledger',
              sub: 'Debit/Credit, GST & Totals',
              color: const Color(0xFF0D9488),
              onTap: () => _openExcelStudio(),
            ),
            _studioToolTile(
              icon: Icons.description_outlined,
              title: 'Word Studio',
              sub: 'Create & Edit .DOCX / .TXT',
              color: const Color(0xFF4338CA),
              onTap: () => _openWordStudio(),
            ),
            _studioToolTile(
              icon: Icons.call_merge_rounded,
              title: 'Merge PDFs',
              sub: 'Combine Multiple PDF Files',
              color: const Color(0xFFB91C1C),
              onTap: _openPdfMergerDialog,
            ),
            _studioToolTile(
              icon: Icons.draw_rounded,
              title: 'Sign & Stamp',
              sub: 'Digital Ink & Official Stamps',
              color: const Color(0xFFB45309),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SignatureAndStampStudio(
                      onSaveSignedPdf: (bytes, name) async {
                        final dir = await _getAccountVaultDir();
                        await File(p.join(dir.path, '$name.pdf')).writeAsBytes(bytes);
                        await _reloadVault();
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECENT WORKSPACE DOCUMENTS',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF475569)),
            ),
            TextButton(
              onPressed: () => setState(() => _tabIndex = 1),
              child: const Text('Open Vault'),
            ),
          ],
        ),
        if (_vaultFiles.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('Your workspace vault is ready. Capture or create a file to begin.'),
              ),
            ),
          )
        else
          ..._vaultFiles.take(6).map(_buildFileCard),
      ],
    );
  }

  Widget _studioToolTile({
    required IconData icon,
    required String title,
    required String sub,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
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

  Widget _buildUniversalVaultTab() {
    final categories = ['ALL', 'PDF', 'XLSX', 'DOCX', 'TXT'];
    final filtered = _vaultFiles.where((f) {
      final matchesSearch = f.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCat = _selectedCategory == 'ALL' || f.ext == _selectedCategory;
      return matchesSearch && matchesCat;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search PDF, Excel, Word, or Text files...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: categories.map((cat) {
              final selected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: selected,
                  onSelected: (_) => setState(() => _
