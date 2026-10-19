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
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matching documents in this category.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _buildFileCard(filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildFileCard(VaultFile file) {
    Color badge = const Color(0xFFDC2626);
    if (file.ext == 'XLSX' || file.ext == 'CSV') badge = const Color(0xFF15803D);
    if (file.ext == 'DOCX') badge = const Color(0xFF1D4ED8);
    if (file.ext == 'TXT') badge = const Color(0xFF475569);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => _openInAppViewer(file),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badge.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            file.ext,
            style: TextStyle(color: badge, fontWeight: FontWeight.w900, fontSize: 11),
          ),
        ),
        title: Row(
          children: [
            if (file.isLocked)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.lock, size: 15, color: Color(0xFFB45309)),
              ),
            Expanded(
              child: Text(
                file.name,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${_formatBytes(file.sizeBytes)} • ${DateFormat('dd MMM yyyy, hh:mm a').format(file.modified)}',
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'view') {
              await _openInAppViewer(file);
            } else if (action == 'external') {
              if (file.isLocked && !await _verifyPinDialog('Unlock ${file.name}')) return;
              await OpenFilex.open(file.path);
            } else if (action == 'pdf_to_word' && file.ext == 'PDF') {
              await _convertPdfToWord(file);
            } else if (action == 'lock') {
              await _toggleFileLock(file);
            } else if (action == 'share') {
              if (file.isLocked && !await _verifyPinDialog('Unlock ${file.name}')) return;
              await Share.shareXFiles([XFile(file.path)], text: file.name);
            } else if (action == 'print' && file.ext == 'PDF') {
              final bytes = await File(file.path).readAsBytes();
              await Printing.layoutPdf(onLayout: (_) async => bytes);
            } else if (action == 'delete') {
              if (file.isLocked && !await _verifyPinDialog('Unlock to Delete')) return;
              await File(file.path).delete();
              await _reloadVault();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'view', child: Text('Open in AN Office Studio')),
            const PopupMenuItem(value: 'external', child: Text('Open External System App')),
            if (file.ext == 'PDF')
              const PopupMenuItem(value: 'pdf_to_word', child: Text('Convert PDF to Word (.docx)')),
            PopupMenuItem(
              value: 'lock',
              child: Text(file.isLocked ? 'Remove PIN Lock' : 'Lock File with PIN'),
            ),
            const PopupMenuItem(value: 'share', child: Text('Share / Cloud Backup')),
            if (file.ext == 'PDF')
              const PopupMenuItem(value: 'print', child: Text('Wireless Print PDF')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete File', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAccountSwitcher() async {
    final newAccCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Multi-User Workspace Profiles',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._accounts.map(
              (acc) => ListTile(
                leading: Icon(
                  acc == _currentAccount ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: const Color(0xFF0F172A),
                ),
                title: Text(acc),
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('active_account', acc);
                  setState(() => _currentAccount = acc);
                  await _reloadVault();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: newAccCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Add New Firm / User Account',
                      isDense: true,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final name = newAccCtrl.text.trim();
                    if (name.isNotEmpty && !_accounts.contains(name)) {
                      final prefs = await SharedPreferences.getInstance();
                      _accounts.add(name);
                      await prefs.setStringList('user_accounts', _accounts);
                      await prefs.setString('active_account', name);
                      setState(() => _currentAccount = name);
                      await _reloadVault();
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Add & Switch'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsAndAccountsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF0F172A),
              foregroundColor: Color(0xFFD4AF37),
              child: Icon(Icons.person_outline),
            ),
            title: Text(_currentAccount, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Isolated Multi-User Vault Directory'),
            trailing: OutlinedButton(
              onPressed: _showAccountSwitcher,
              child: const Text('Switch'),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.cloud_sync_outlined, color: Color(0xFF1D4ED8)),
            title: const Text('Automated Cloud Drive Backup Sync'),
            subtitle: const Text('Ready to export/sync workspace bundle to Google Drive / OneDrive'),
            value: _autoCloudSync,
            onChanged: (v) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('auto_cloud_sync', v);
              setState(() => _autoCloudSync = v);
            },
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Default Tiered PDF Compression',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 35, label: Text('Extreme (35%)')),
                    ButtonSegment(value: 75, label: Text('Balanced (75%)')),
                    ButtonSegment(value: 95, label: Text('Ultra HD (95%)')),
                  ],
                  selected: {_defaultCompression},
                  onSelectionChanged: (s) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('default_compression', s.first);
                    setState(() => _defaultCompression = s.first);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_person_outlined, color: Color(0xFFB45309)),
            title: const Text('Master PIN & Document Password Lock'),
            subtitle: Text(_masterPin == null || _masterPin!.isEmpty ? 'Not Set' : '4-Digit PIN Active'),
            trailing: Switch(
              value: _masterPin != null && _masterPin!.isNotEmpty,
              onChanged: (enable) async {
                final prefs = await SharedPreferences.getInstance();
                if (!enable) {
                  await prefs.remove('master_pin');
                  setState(() => _masterPin = null);
                } else {
                  final ctrl = TextEditingController();
                  final pin = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Set 4-Digit Master PIN'),
                      content: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        decoration: const InputDecoration(labelText: 'Enter 4-Digit PIN'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                          child: const Text('Save PIN'),
                        ),
                      ],
                    ),
                  );
                  if (pin != null && pin.length == 4) {
                    await prefs.setString('master_pin', pin);
                    setState(() => _masterPin = pin);
                  }
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_outlined, color: Color(0xFF0F172A)),
            title: const Text('Designed & Engineered by Adesh Narang'),
            subtitle: const Text('Official Portal: https://adeshnarang.in'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse('https://adeshnarang.in')),
          ),
        ),
      ],
    );
  }
}

class InteractiveScanStudio extends StatefulWidget {
  final List<String> initialPaths;
  final int defaultCompression;
  final Future<void> Function(Uint8List pdfBytes, String fileName, bool lockFile) onSavePdf;

  const InteractiveScanStudio({
    super.key,
    required this.initialPaths,
    required this.defaultCompression,
    required this.onSavePdf,
  });

  @override
  State<InteractiveScanStudio> createState() => _InteractiveScanStudioState();
}

class _InteractiveScanStudioState extends State<InteractiveScanStudio> {
  late List<EditablePageItem> _pages;
  int _idx = 0;
  late int _compressionQuality;
  bool _lockWithPin = false;
  bool _isCompiling = false;
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _pages = widget.initialPaths.map((p) => EditablePageItem(imagePath: p)).toList();
    _compressionQuality = widget.defaultCompression;
    _nameCtrl = TextEditingController(
      text: 'AN_Scan_${DateFormat('ddMMM_HHmm').format(DateTime.now())}',
    );
  }

  Future<void> _addTextOverlayDialog() async {
    final ctrl = TextEditingController(text: _pages[_idx].overlayText);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Movable Page Annotation / Stamp'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Annotation Text (e.g., VERIFIED / Invoice #)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (res != null) {
      setState(() => _pages[_idx].overlayText = res);
    }
  }

  Future<void> _openReorderSheet() async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Long-Press & Drag to Reorder Pages',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: _pages.length,
                onReorder: (oldIdx, newIdx) {
                  setState(() {
                    if (newIdx > oldIdx) newIdx -= 1;
                    final item = _pages.removeAt(oldIdx);
                    _pages.insert(newIdx, item);
                    _idx = 0;
                  });
                  setModal(() {});
                },
                itemBuilder: (_, i) => ListTile(
                  key: ValueKey(_pages[i].imagePath + i.toString()),
                  leading: Image.file(File(_pages[i].imagePath), width: 42, height: 42, fit: BoxFit.cover),
                  title: Text('Page ${i + 1}'),
                  subtitle: Text('Filter: ${_pages[i].filterMode.toUpperCase()}'),
                  trailing: const Icon(Icons.drag_handle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<double>? _getFilterMatrix(String mode) {
    if (mode == 'bw') {
      return [
        0.35, 0.55, 0.10, 0, 25,
        0.35, 0.55, 0.10, 0, 25,
        0.35, 0.55, 0.10, 0, 25,
        0,    0,    0,    1, 0,
      ];
    } else if (mode == 'gray') {
      return [
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0,      0,      0,      1, 0,
      ];
    } else if (mode == 'magic') {
      return [
        1.25, 0,    0,    0, 10,
        0,    1.25, 0,    0, 10,
        0,    0,    1.25, 0, 10,
        0,    0,    0,    1, 0,
      ];
    }
    return null;
  }

  Future<void> _compileAndSavePdf() async {
    setState(() => _isCompiling = true);
    try {
      final pdf = pw.Document();
      for (final pageItem in _pages) {
        final compressed = await FlutterImageCompress.compressWithFile(
          pageItem.imagePath,
          quality: _compressionQuality,
          rotate: pageItem.quarterTurns * 90,
        );
        final bytes = compressed ?? await File(pageItem.imagePath).readAsBytes();
        final img = pw.MemoryImage(bytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(14),
            build: (_) => pw.Stack(
              children: [
                pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
                if (pageItem.overlayText.isNotEmpty)
                  pw.Positioned(
                    left: pageItem.overlayPosition.dx,
                    top: pageItem.overlayPosition.dy,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.blue900, width: 1.5),
                      ),
                      child: pw.Text(
                        pageItem.overlayText,
                        style: pw.TextStyle(
                          color: PdfColors.blue900,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      final outBytes = await pdf.save();
      await widget.onSavePdf(outBytes, _nameCtrl.text.trim(), _lockWithPin);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compiled PDF Saved to AN Office Vault!')),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isCompiling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _pages[_idx];
    final matrix = _getFilterMatrix(current.filterMode);

    Widget previewImg = RotatedBox(
      quarterTurns: current.quarterTurns,
      child: Image.file(File(current.imagePath), fit: BoxFit.contain),
    );
    if (matrix != null) {
      previewImg = ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: previewImg);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Page ${_idx + 1} of ${_pages.length}'),
        actions: [
          IconButton(
            tooltip: 'Rotate 90°',
            onPressed: () => setState(() => current.quarterTurns = (current.quarterTurns + 1) % 4),
            icon: const Icon(Icons.rotate_right),
          ),
          IconButton(
            tooltip: 'Add Movable Text',
            onPressed: _addTextOverlayDialog,
            icon: const Icon(Icons.text_fields),
          ),
          IconButton(
            tooltip: 'Reorder Pages',
            onPressed: _openReorderSheet,
            icon: const Icon(Icons.low_priority),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'PDF Document Name',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: 'Toggle PIN Lock on Save',
                  icon: Icon(
                    _lockWithPin ? Icons.lock : Icons.lock_open,
                    color: _lockWithPin ? const Color(0xFFB45309) : Colors.grey,
                  ),
                  onPressed: () => setState(() => _lockWithPin = !_lockWithPin),
                ),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _idx = i),
              itemBuilder: (_, i) => Stack(
                alignment: Alignment.center,
                children: [
                  Padding(padding: const EdgeInsets.all(12), child: previewImg),
                  if (current.overlayText.isNotEmpty)
                    Positioned(
                      left: current.overlayPosition.dx,
                      top: current.overlayPosition.dy,
                      child: GestureDetector(
                        onPanUpdate: (d) {
                          setState(() {
                            current.overlayPosition += d.delta;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.88),
                            border: Border.all(color: const Color(0xFF0F172A), width: 2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            current.overlayText,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final mode in [
                        ('original', 'Original'),
                        ('magic', 'Magic Color'),
                        ('bw', 'High-Contrast B&W'),
                        ('gray', 'Grayscale'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(mode.$2),
                            selected: current.filterMode == mode.$1,
                            onSelected: (_) => setState(() => current.filterMode = mode.$1),
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    const Text('Size Compression:', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _compressionQuality.toDouble(),
                        min: 25,
                        max: 100,
                        divisions: 15,
                        label: '$_compressionQuality%',
                        onChanged: (v) => setState(() => _compressionQuality = v.round()),
                      ),
                    ),
                    Text('$_compressionQuality%', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isCompiling ? null : _compileAndSavePdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: Text(_isCompiling ? 'Compiling PDF...' : 'Save High-Clarity PDF to Vault'),
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

class ExcelSpreadsheetStudio extends StatefulWidget {
  final List<Map<String, String>>? prefilledRows;
  final String? existingFilePath;
  final Future<void> Function(Uint8List bytes, String fileNameWithExt) onSaveFile;

  const ExcelSpreadsheetStudio({
    super.key,
    this.prefilledRows,
    this.existingFilePath,
    required this.onSaveFile,
  });

  @override
  State<ExcelSpreadsheetStudio> createState() => _ExcelSpreadsheetStudioState();
}

class _ExcelSpreadsheetStudioState extends State<ExcelSpreadsheetStudio> {
  late TextEditingController _nameCtrl;
  final TextEditingController _openingBalCtrl = TextEditingController(text: '0.00');
  double _gstPercent = 0.0;
  final List<Map<String, TextEditingController>> _rows = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: widget.existingFilePath != null
          ? p.basenameWithoutExtension(widget.existingFilePath!)
          : 'Ledger_${DateFormat('ddMMM_HHmm').format(DateTime.now())}',
    );
    _initRows();
  }

  Future<void> _initRows() async {
    if (widget.existingFilePath != null && File(widget.existingFilePath!).existsSync()) {
      try {
        final bytes = await File(widget.existingFilePath!).readAsBytes();
        final excel = xls.Excel.decodeBytes(bytes);
        for (final table in excel.tables.keys) {
          final sheet = excel.tables[table]!;
          for (int r = 1; r < sheet.rows.length; r++) {
            final row = sheet.rows[r];
            final col0 = row.isNotEmpty ? (row[0]?.value?.toString() ?? '') : '';
            if (col0.startsWith('GRAND TOTAL')) continue;
            final col1 = row.length > 1 ? (row[1]?.value?.toString() ?? '1') : '1';
            final col2 = row.length > 2 ? (row[2]?.value?.toString() ?? '0') : '0';
            _rows.add({
              'item': TextEditingController(text: col0),
              'qty': TextEditingController(text: col1),
              'rate': TextEditingController(text: col2),
            });
          }
          break;
        }
      } catch (_) {}
    } else if (widget.prefilledRows != null && widget.prefilledRows!.isNotEmpty) {
      for (final r in widget.prefilledRows!) {
        _rows.add({
          'item': TextEditingController(text: r['item'] ?? ''),
          'qty': TextEditingController(text: r['qty'] ?? '1'),
          'rate': TextEditingController(text: r['rate'] ?? '0'),
        });
      }
    }

    if (_rows.isEmpty) {
      for (int i = 0; i < 6; i++) {
        _rows.add({
          'item': TextEditingController(),
          'qty': TextEditingController(text: '1'),
          'rate': TextEditingController(text: '0.00'),
        });
      }
    }
    if (mounted) setState(() {});
  }

  double _rowTotal(int i) {
    final q = double.tryParse(_rows[i]['qty']!.text) ?? 0.0;
    final r = double.tryParse(_rows[i]['rate']!.text) ?? 0.0;
    return q * r;
  }

  double _subTotal() {
    double sum = double.tryParse(_openingBalCtrl.text) ?? 0.0;
    for (int i = 0; i < _rows.length; i++) {
      sum += _rowTotal(i);
    }
    return sum;
  }

  double _grandTotal() {
    final sub = _subTotal();
    return sub + (sub * (_gstPercent / 100.0));
  }

  Future<void> _saveSpreadsheet({required bool asCsv}) async {
    final baseName = _nameCtrl.text.trim().isEmpty ? 'Ledger' : _nameCtrl.text.trim();
    if (asCsv) {
      final sb = StringBuffer();
      sb.writeln('Particulars,Qty,Rate,Amount');
      for (int i = 0; i < _rows.length; i++) {
        sb.writeln(
          '"${_rows[i]['item']!.text}",${_rows[i]['qty']!.text},${_rows[i]['rate']!.text},${_rowTotal(i).toStringAsFixed(2)}',
        );
      }
      sb.writeln('GRAND TOTAL,,,${_grandTotal().toStringAsFixed(2)}');
      await widget.onSaveFile(Uint8List.fromList(utf8.encode(sb.toString())), '$baseName.csv');
    } else {
      final excel = xls.Excel.createExcel();
      final sheet = excel['Sheet1'];
      sheet.appendRow([
        xls.TextCellValue('Particulars / Account Head'),
        xls.TextCellValue('Qty / Cr'),
        xls.TextCellValue('Rate / Dr'),
        xls.TextCellValue('Net Amount'),
      ]);
      for (int i = 0; i < _rows.length; i++) {
        final txt = _rows[i]['item']!.text;
        final q = double.tryParse(_rows[i]['qty']!.text) ?? 0.0;
        final r = double.tryParse(_rows[i]['rate']!.text) ?? 0.0;
        if (txt.isNotEmpty || (q * r) != 0) {
          sheet.appendRow([
            xls.TextCellValue(txt),
            xls.DoubleCellValue(q),
            xls.DoubleCellValue(r),
            xls.DoubleCellValue(q * r),
          ]);
        }
      }
      sheet.appendRow([
        xls.TextCellValue('GRAND TOTAL (Incl. GST $_gstPercent%)'),
        xls.TextCellValue(''),
        xls.TextCellValue(''),
        xls.DoubleCellValue(_grandTotal()),
      ]);
      final encoded = excel.encode();
      if (encoded != null) {
        await widget.onSaveFile(Uint8List.fromList(encoded), '$baseName.xlsx');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $baseName.${asCsv ? "csv" : "xlsx"} to Vault!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Excel & Accounting Ledger'),
        actions: [
          IconButton(
            tooltip: 'Add Entry Row',
            onPressed: () {
              setState(() {
                _rows.add({
                  'item': TextEditingController(),
                  'qty': TextEditingController(text: '1'),
                  'rate': TextEditingController(text: '0.00'),
                });
              });
            },
            icon: const Icon(Icons.add_box_outlined),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.save_alt),
            onSelected: (v) => _saveSpreadsheet(asCsv: v == 'CSV'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'XLSX', child: Text('Export Excel (.xlsx)')),
              PopupMenuItem(value: 'CSV', child: Text('Export Tally/Busy CSV (.csv)')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ledger File Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _openingBalCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Opening Bal (₹)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('GST Slab: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  for (final gst in [0.0, 5.0, 12.0, 18.0, 28.0])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('${gst.toInt()}%'),
                        selected: _gstPercent == gst,
                        onSelected: (_) => setState(() => _gstPercent = gst),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _rows.length,
              itemBuilder: (_, i) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _rows[i]['item'],
                          decoration: InputDecoration(labelText: 'Item / Party #${i + 1}', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _rows[i]['qty'],
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _rows[i]['rate'],
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'Rate', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 74,
                        child: Text(
                          '₹${_rowTotal(i).toStringAsFixed(1)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF0F172A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'NET LEDGER TOTAL (GST ${_gstPercent.toInt()}%)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  '₹ ${_grandTotal().toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFFD4AF37),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
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

class SignatureAndStampStudio extends StatefulWidget {
  final Future<void> Function(Uint8List pdfBytes, String name) onSaveSignedPdf;

  const SignatureAndStampStudio({super.key, required this.onSaveSignedPdf});

  @override
  State<SignatureAndStampStudio> createState() => _SignatureAndStampStudioState();
}

class _SignatureAndStampStudioState extends State<SignatureAndStampStudio> {
  final List<Offset?> _points = [];
  final GlobalKey _boundaryKey = GlobalKey();
  Color _inkColor = const Color(0xFF0F172A);
  String _selectedStamp = 'APPROVED';

  Future<void> _exportSignedDocument() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final img = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    final pngBytes = byteData.buffer.asUint8List();
    final pdf = pw.Document();
    final pwImg = pw.MemoryImage(pngBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blue900, width: 2),
                ),
                child: pw.Text(
                  'OFFICIAL STAMP: $_selectedStamp • AN OFFICE',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Image(pwImg, width: 320),
              pw.SizedBox(height: 10),
              pw.Text(
                'Digitally Signed on ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
      ),
    );

    await widget.onSaveSignedPdf(
      await pdf.save(),
      'Signed_${_selectedStamp}_${DateFormat('ddMMM_HHmm').format(DateTime.now())}',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed & Stamped PDF Saved to Vault!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signature & Official Stamp Pad'),
        actions: [
          IconButton(
            tooltip: 'Clear Pad',
            onPressed: () => setState(() => _points.clear()),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: 'Save Signed PDF',
            onPressed: _exportSignedDocument,
            icon: const Icon(Icons.check_circle_outline),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('Official Stamp: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final st in ['APPROVED', 'VERIFIED', 'PAID', 'RECEIVED', 'CONFIDENTIAL'])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(st),
                        selected: _selectedStamp == st,
                        onSelected: (_) => setState(() => _selectedStamp = st),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Ink Color: '),
                for (final c in [
                  const Color(0xFF0F172A),
                  const Color(0xFF1D4ED8),
                  const Color(0xFFB91C1C),
                  const Color(0xFF15803D),
                ])
                  GestureDetector(
                    onTap: () => setState(() => _inkColor = c),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _inkColor == c ? const Color(0xFFD4AF37) : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RepaintBoundary(
                key: _boundaryKey,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF0F172A), width: 2),
                  ),
                  child: GestureDetector(
                    onPanUpdate: (d) {
                      final box = _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
                      if (box != null) {
                        setState(() => _points.add(box.globalToLocal(d.globalPosition)));
                      }
                    },
                    onPanEnd: (_) => _points.add(null),
                    child: CustomPaint(
                      painter: _InkPainter(_points, _inkColor),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  final List<Offset?> points;
  final Color color;
  _InkPainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.8;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
