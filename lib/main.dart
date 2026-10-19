import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_cropper/image_cropper.dart';
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
        scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Porcelain White
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A), // Executive Navy
          primary: const Color(0xFF0F172A),
          secondary: const Color(0xFFB45309), // Executive Gold Accent
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
        ),
      ),
      home: const ExecutiveHomeScreen(),
    );
  }
}

class SavedDocument {
  final String name;
  final String path;
  final String type; // PDF, DOCX, XLSX, TXT
  final DateTime modified;
  final int sizeBytes;

  SavedDocument({
    required this.name,
    required this.path,
    required this.type,
    required this.modified,
    required this.sizeBytes,
  });
}

class ExecutiveHomeScreen extends StatefulWidget {
  const ExecutiveHomeScreen({super.key});

  @override
  State<ExecutiveHomeScreen> createState() => _ExecutiveHomeScreenState();
}

class _ExecutiveHomeScreenState extends State<ExecutiveHomeScreen> {
  int _selectedIndex = 0;
  List<SavedDocument> _documents = [];
  String _searchQuery = '';
  String _activeProfile = 'Executive Admin';
  String? _appPin;
  bool _isUnlocked = false;
  int _compressionQuality = 80; // Default High Quality (80%)

  @override
  void initState() {
    super.initState();
    _loadSettingsAndFiles();
  }

  Future<void> _loadSettingsAndFiles() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _activeProfile = prefs.getString('profile_name') ?? 'Adesh Narang';
      _appPin = prefs.getString('app_pin');
      _compressionQuality = prefs.getInt('compression_quality') ?? 80;
      _isUnlocked = (_appPin == null || _appPin!.isEmpty);
    });
    await _refreshFileVault();
  }

  Future<Directory> _getVaultDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final vault = Directory(p.join(baseDir.path, 'AN_Office_Vault'));
    if (!await vault.exists()) {
      await vault.create(recursive: true);
    }
    return vault;
  }

  Future<void> _refreshFileVault() async {
    final vault = await _getVaultDirectory();
    final entities = vault.listSync();
    final List<SavedDocument> docs = [];

    for (var entity in entities) {
      if (entity is File) {
        final stat = await entity.stat();
        final ext = p.extension(entity.path).replaceAll('.', '').toUpperCase();
        if (['PDF', 'DOCX', 'XLSX', 'TXT', 'PNG', 'JPG'].contains(ext)) {
          docs.add(
            SavedDocument(
              name: p.basename(entity.path),
              path: entity.path,
              type: ext,
              modified: stat.modified,
              sizeBytes: stat.size,
            ),
          );
        }
      }
    }
    docs.sort((a, b) => b.modified.compareTo(a.modified));
    if (mounted) {
      setState(() {
        _documents = docs;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  // ===========================================================================
  // 1. SMART AI SCANNER + PRE-SAVE STUDIO (CROP, FILTER, COMPRESS, PDF EXPORT)
  // ===========================================================================
  Future<void> _startSmartScan({bool useGallery = false}) async {
    List<String> capturedPaths = [];

    try {
      if (!useGallery) {
        final scanner = DocumentScanner(
          options: DocumentScannerOptions(
            documentFormat: DocumentFormat.jpeg,
            mode: ScannerMode.full,
            pageLimit: 25,
            isGalleryImport: true,
          ),
        );
        final result = await scanner.scanDocument();
        if (result.images.isNotEmpty) {
          capturedPaths.addAll(result.images);
        }
      } else {
        final picker = ImagePicker();
        final files = await picker.pickMultiImage();
        capturedPaths.addAll(files.map((e) => e.path));
      }
    } catch (e) {
      // Fallback to standard camera if device lacks Play Services ML Kit
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) capturedPaths.add(photo.path);
    }

    if (capturedPaths.isEmpty || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanReviewStudio(
          initialImages: capturedPaths,
          defaultCompression: _compressionQuality,
          onSavePdf: (pdfBytes, fileName) async {
            final vault = await _getVaultDirectory();
            final cleanName = fileName.endsWith('.pdf') ? fileName : '$fileName.pdf';
            final outFile = File(p.join(vault.path, cleanName));
            await outFile.writeAsBytes(pdfBytes);
            await _refreshFileVault();
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // 2. OFFLINE OCR TEXT EXTRACTOR -> EXPORT TO PDF, DOCX (WORD), OR TXT
  // ===========================================================================
  Future<void> _runOcrExtractor() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Extracting Offline OCR Text...')),
          ],
        ),
      ),
    );

    String extractedText = '';
    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await recognizer.processImage(inputImage);
      extractedText = recognized.text;
      await recognizer.close();
    } catch (e) {
      extractedText = 'Error extracting text: $e';
    }

    if (!mounted) return;
    Navigator.pop(context); // Close loader

    _openWordAndTextEditor(
      initialTitle: 'OCR_${DateFormat('ddMMM_HHmm').format(DateTime.now())}',
      initialContent: extractedText.isEmpty
          ? 'No readable text detected. You can type manually here.'
          : extractedText,
    );
  }

  // ===========================================================================
  // 3. WORD (.DOCX) & TEXT (.TXT) STUDIO EDITOR
  // ===========================================================================
  void _openWordAndTextEditor({String initialTitle = '', String initialContent = ''}) {
    final titleCtrl = TextEditingController(
      text: initialTitle.isEmpty
          ? 'Doc_${DateFormat('ddMMM_HHmm').format(DateTime.now())}'
          : initialTitle,
    );
    final bodyCtrl = TextEditingController(text: initialContent);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('Word & Document Writer'),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.save_alt),
                onSelected: (format) async {
                  final vault = await _getVaultDirectory();
                  final baseName = titleCtrl.text.trim().isEmpty
                      ? 'Document'
                      : titleCtrl.text.trim();

                  if (format == 'TXT') {
                    final file = File(p.join(vault.path, '$baseName.txt'));
                    await file.writeAsString(bodyCtrl.text);
                  } else if (format == 'DOCX') {
                    final docxBytes = _buildValidDocxBytes(bodyCtrl.text);
                    final file = File(p.join(vault.path, '$baseName.docx'));
                    await file.writeAsBytes(docxBytes);
                  } else if (format == 'PDF') {
                    final doc = pw.Document();
                    doc.addPage(
                      pw.MultiPage(
                        pageFormat: PdfPageFormat.a4,
                        build: (_) => [
                          pw.Header(level: 0, text: baseName),
                          pw.Paragraph(text: bodyCtrl.text),
                        ],
                      ),
                    );
                    final file = File(p.join(vault.path, '$baseName.pdf'));
                    await file.writeAsBytes(await doc.save());
                  }

                  await _refreshFileVault();
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Saved $baseName.$format to Vault')),
                    );
                    Navigator.pop(ctx);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'DOCX', child: Text('Export as Word (.docx)')),
                  PopupMenuItem(value: 'PDF', child: Text('Export as PDF (.pdf)')),
                  PopupMenuItem(value: 'TXT', child: Text('Export as Plain Text (.txt)')),
                ],
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Document File Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description_outlined),
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
                      labelText: 'Document Content',
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

  // Generates a genuine OpenXML .docx archive offline
  Uint8List _buildValidDocxBytes(String content) {
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

    final escapedParagraphs = content
        .split('\n')
        .map((line) {
          final safe = const HtmlEscape().convert(line);
          return '<w:p><w:r><w:t>$safe</w:t></w:r></w:p>';
        })
        .join('');

    final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>$escapedParagraphs</w:body>
</w:document>''';

    archive.addFile(ArchiveFile('[Content_Types].xml', contentTypesXml.length, utf8.encode(contentTypesXml)));
    archive.addFile(ArchiveFile('_rels/.rels', relsXml.length, utf8.encode(relsXml)));
    final docBytes = utf8.encode(documentXml);
    archive.addFile(ArchiveFile('word/document.xml', docBytes.length, docBytes));

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  // ===========================================================================
  // 4. EXCEL (.XLSX) LEDGER & SPREADSHEET STUDIO
  // ===========================================================================
  void _openExcelLedgerStudio() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExcelLedgerScreen(
          onSaveExcel: (bytes, fileName) async {
            final vault = await _getVaultDirectory();
            final file = File(p.join(vault.path, '$fileName.xlsx'));
            await file.writeAsBytes(bytes);
            await _refreshFileVault();
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // 5. DIGITAL SIGNATURE STUDIO
  // ===========================================================================
  void _openSignatureStudio() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignaturePadStudio(
          onSaveSignaturePdf: (pdfBytes, name) async {
            final vault = await _getVaultDirectory();
            final file = File(p.join(vault.path, '$name.pdf'));
            await file.writeAsBytes(pdfBytes);
            await _refreshFileVault();
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // UI LOCK SCREEN & MAIN SCAFFOLD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    if (!_isUnlocked) {
      final pinCtrl = TextEditingController();
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 56, color: Color(0xFF0F172A)),
                    const SizedBox(height: 12),
                    const Text(
                      'AN Office Vault Locked',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Enter 4-Digit Security PIN',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        if (pinCtrl.text == _appPin) {
                          setState(() => _isUnlocked = true);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Incorrect PIN')),
                          );
                        }
                      },
                      icon: const Icon(Icons.login),
                      label: const Text('Unlock Studio'),
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
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 19),
            ),
            Text(
              'Executive Suite • $_activeProfile',
              style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Vault',
            onPressed: _refreshFileVault,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboardTab(),
          _buildVaultTab(),
          _buildSettingsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        onPressed: () => _startSmartScan(useGallery: false),
        icon: const Icon(Icons.document_scanner),
        label: const Text('Smart Scan'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Studio'),
          NavigationDestination(icon: Icon(Icons.folder_copy_outlined), label: 'File Vault'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Executive'),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Executive Banner
        Container(
          padding: const EdgeInsets.all(20),
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
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD4AF37)),
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
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Offline Document & Ledger Studio',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_documents.length} files stored locally • 100% Private',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'CORE TOOLS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            _toolCard(
              icon: Icons.camera_enhance_rounded,
              title: 'HD AI Scanner',
              subtitle: 'Auto-edge, crop & filter',
              color: const Color(0xFF0F172A),
              onTap: () => _startSmartScan(useGallery: false),
            ),
            _toolCard(
              icon: Icons.photo_library_outlined,
              title: 'Images to PDF',
              subtitle: 'Batch import & compress',
              color: const Color(0xFF1D4ED8),
              onTap: () => _startSmartScan(useGallery: true),
            ),
            _toolCard(
              icon: Icons.text_snippet_outlined,
              title: 'OCR to Word',
              subtitle: 'Extract text to .docx/.txt',
              color: const Color(0xFF047857),
              onTap: _runOcrExtractor,
            ),
            _toolCard(
              icon: Icons.table_chart_outlined,
              title: 'Excel Ledger',
              subtitle: 'Auto-total & .xlsx export',
              color: const Color(0xFF15803D),
              onTap: _openExcelLedgerStudio,
            ),
            _toolCard(
              icon: Icons.edit_document,
              title: 'Word Writer',
              subtitle: 'Create .docx, .pdf & .txt',
              color: const Color(0xFF4338CA),
              onTap: () => _openWordAndTextEditor(),
            ),
            _toolCard(
              icon: Icons.draw_outlined,
              title: 'Sign & Stamp',
              subtitle: 'Digital ink signature pad',
              color: const Color(0xFFB45309),
              onTap: _openSignatureStudio,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECENT VAULT FILES',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 1.1,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _selectedIndex = 1),
              child: const Text('View All'),
            ),
          ],
        ),
        if (_documents.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No documents yet. Tap "Smart Scan" or create a Word/Excel file.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            ),
          )
        else
          ..._documents.take(5).map(_buildDocumentTile),
      ],
    );
  }

  Widget _toolCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
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

  Widget _buildVaultTab() {
    final filtered = _documents.where((doc) {
      return doc.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search PDF, Excel, Word, or Text files...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matching files in Vault.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _buildDocumentTile(filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildDocumentTile(SavedDocument doc) {
    Color badgeColor = const Color(0xFFDC2626);
    if (doc.type == 'XLSX') badgeColor = const Color(0xFF15803D);
    if (doc.type == 'DOCX') badgeColor = const Color(0xFF1D4ED8);
    if (doc.type == 'TXT') badgeColor = const Color(0xFF475569);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => OpenFilex.open(doc.path),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            doc.type,
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
        title: Text(
          doc.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_formatSize(doc.sizeBytes)} • ${DateFormat('dd MMM yyyy, hh:mm a').format(doc.modified)}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'open') {
              await OpenFilex.open(doc.path);
            } else if (action == 'share') {
              await Share.shareXFiles([XFile(doc.path)], text: doc.name);
            } else if (action == 'print' && doc.type == 'PDF') {
              final bytes = await File(doc.path).readAsBytes();
              await Printing.layoutPdf(onLayout: (_) async => bytes);
            } else if (action == 'delete') {
              await File(doc.path).delete();
              await _refreshFileVault();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'open', child: Text('Open System Viewer')),
            const PopupMenuItem(value: 'share', child: Text('Share / WhatsApp')),
            if (doc.type == 'PDF')
              const PopupMenuItem(value: 'print', child: Text('Print / Save PDF')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete File', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF0F172A),
              foregroundColor: Color(0xFFD4AF37),
              child: Text('AN', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            title: Text(_activeProfile, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Active Workspace Profile'),
            trailing: TextButton(
              onPressed: () async {
                final ctrl = TextEditingController(text: _activeProfile);
                final res = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Switch Workspace Profile'),
                    content: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(labelText: 'Profile Name'),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                if (res != null && res.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('profile_name', res);
                  setState(() => _activeProfile = res);
                }
              },
              child: const Text('Edit'),
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
                const Text(
                  'Default PDF Scan Compression Tier',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Controls file size when compiling scanned camera pages into PDF.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 45, label: Text('Max Small (45%)')),
                    ButtonSegment(value: 75, label: Text('Balanced (75%)')),
                    ButtonSegment(value: 95, label: Text('Ultra HD (95%)')),
                  ],
                  selected: {_compressionQuality},
                  onSelectionChanged: (setVal) async {
                    final val = setVal.first;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('compression_quality', val);
                    setState(() => _compressionQuality = val);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Vault PIN Lock'),
            subtitle: Text(_appPin == null || _appPin!.isEmpty ? 'Disabled' : 'PIN Protection Active'),
            trailing: Switch(
              value: _appPin != null && _appPin!.isNotEmpty,
              onChanged: (enable) async {
                final prefs = await SharedPreferences.getInstance();
                if (!enable) {
                  await prefs.remove('app_pin');
                  setState(() => _appPin = null);
                } else {
                  final pinCtrl = TextEditingController();
                  final newPin = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Set 4-Digit Vault PIN'),
                      content: TextField(
                        controller: pinCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        decoration: const InputDecoration(labelText: 'Enter 4 digits'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, pinCtrl.text.trim()),
                          child: const Text('Enable Lock'),
                        ),
                      ],
                    ),
                  );
                  if (newPin != null && newPin.length == 4) {
                    await prefs.setString('app_pin', newPin);
                    setState(() => _appPin = newPin);
                  }
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.language_outlined, color: Color(0xFFB45309)),
            title: const Text('Built by Adesh Narang'),
            subtitle: const Text('adeshnarang.in • Executive Productivity Suite'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(Uri.parse('https://adeshnarang.in')),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// SCAN REVIEW STUDIO (CROP, B&W CONTRAST FILTER, COMPRESSION & PDF EXPORT)
// =============================================================================
class ScanReviewStudio extends StatefulWidget {
  final List<String> initialImages;
  final int defaultCompression;
  final Future<void> Function(Uint8List pdfBytes, String fileName) onSavePdf;

  const ScanReviewStudio({
    super.key,
    required this.initialImages,
    required this.defaultCompression,
    required this.onSavePdf,
  });

  @override
  State<ScanReviewStudio> createState() => _ScanReviewStudioState();
}

class _ScanReviewStudioState extends State<ScanReviewStudio> {
  late List<String> _imagePaths;
  int _currentIndex = 0;
  bool _highContrastBw = false;
  late int _quality;
  bool _isSaving = false;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _imagePaths = List.from(widget.initialImages);
    _quality = widget.defaultCompression;
    _nameController = TextEditingController(
      text: 'AN_Scan_${DateFormat('ddMMM_HHmm').format(DateTime.now())}',
    );
  }

  Future<void> _cropCurrentPage() async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: _imagePaths[_currentIndex],
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Adjust Edges & Crop',
          toolbarColor: const Color(0xFF0F172A),
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
      ],
    );
    if (cropped != null) {
      setState(() {
        _imagePaths[_currentIndex] = cropped.path;
      });
    }
  }

  Future<void> _exportCompiledPdf() async {
    setState(() => _isSaving = true);
    try {
      final pdf = pw.Document();

      for (final imgPath in _imagePaths) {
        final compressedBytes = await FlutterImageCompress.compressWithFile(
          imgPath,
          quality: _quality,
        );
        final finalBytes = compressedBytes ?? await File(imgPath).readAsBytes();
        final pwImage = pw.MemoryImage(finalBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(16),
            build: (_) => pw.Center(
              child: pw.Image(pwImage, fit: pw.BoxFit.contain),
            ),
          ),
        );
      }

      final bytes = await pdf.save();
      await widget.onSavePdf(bytes, _nameController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF Saved to AN Office Vault!')),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Page ${_currentIndex + 1} of ${_imagePaths.length}'),
        actions: [
          IconButton(
            tooltip: 'Crop Page',
            onPressed: _cropCurrentPage,
            icon: const Icon(Icons.crop),
          ),
          IconButton(
            tooltip: 'Toggle High-Contrast Clean Filter',
            onPressed: () => setState(() => _highContrastBw = !_highContrastBw),
            icon: Icon(_highContrastBw ? Icons.filter_b_and_w : Icons.wb_sunny_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Output PDF File Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.picture_as_pdf_outlined),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              itemCount: _imagePaths.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, idx) {
                Widget img = Image.file(File(_imagePaths[idx]), fit: BoxFit.contain);
                if (_highContrastBw) {
                  img = ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      0.33, 0.59, 0.11, 0, 20,
                      0.33, 0.59, 0.11, 0, 20,
                      0.33, 0.59, 0.11, 0, 20,
                      0,    0,    0,    1, 0,
                    ]),
                    child: img,
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: img,
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Compression Quality:', style: TextStyle(fontWeight: FontWeight.w600)),
                    Expanded(
                      child: Slider(
                        value: _quality.toDouble(),
                        min: 30,
                        max: 100,
                        divisions: 7,
                        label: '$_quality%',
                        onChanged: (v) => setState(() => _quality = v.round()),
                      ),
                    ),
                    Text('$_quality%'),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _exportCompiledPdf,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_isSaving ? 'Building PDF...' : 'Save PDF to Vault'),
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

// =============================================================================
// EXCEL LEDGER STUDIO (.XLSX EXPORT WITH AUTO-TOTALS)
// =============================================================================
class ExcelLedgerScreen extends StatefulWidget {
  final Future<void> Function(Uint8List bytes, String fileName) onSaveExcel;

  const ExcelLedgerScreen({super.key, required this.onSaveExcel});

  @override
  State<ExcelLedgerScreen> createState() => _ExcelLedgerScreenState();
}

class _ExcelLedgerScreenState extends State<ExcelLedgerScreen> {
  final TextEditingController _fileNameCtrl = TextEditingController(
    text: 'Ledger_${DateFormat('ddMMM').format(DateTime.now())}',
  );

  final List<Map<String, TextEditingController>> _rows = List.generate(
    6,
    (index) => {
      'item': TextEditingController(text: index == 0 ? 'Opening Entry' : ''),
      'qty': TextEditingController(text: index == 0 ? '1' : ''),
      'rate': TextEditingController(text: index == 0 ? '0.00' : ''),
    },
  );

  double _calculateRowAmount(int index) {
    final q = double.tryParse(_rows[index]['qty']!.text) ?? 0.0;
    final r = double.tryParse(_rows[index]['rate']!.text) ?? 0.0;
    return q * r;
  }

  double _calculateGrandTotal() {
    double sum = 0;
    for (int i = 0; i < _rows.length; i++) {
      sum += _calculateRowAmount(i);
    }
    return sum;
  }

  Future<void> _exportXlsx() async {
    final excel = xls.Excel.createExcel();
    final sheet = excel['Sheet1'];

    sheet.appendRow([
      xls.TextCellValue('Particulars / Item'),
      xls.TextCellValue('Qty'),
      xls.TextCellValue('Rate'),
      xls.TextCellValue('Amount'),
    ]);

    for (int i = 0; i < _rows.length; i++) {
      final item = _rows[i]['item']!.text;
      final qty = double.tryParse(_rows[i]['qty']!.text) ?? 0.0;
      final rate = double.tryParse(_rows[i]['rate']!.text) ?? 0.0;
      final amt = qty * rate;
      if (item.isNotEmpty || amt != 0) {
        sheet.appendRow([
          xls.TextCellValue(item),
          xls.DoubleCellValue(qty),
          xls.DoubleCellValue(rate),
          xls.DoubleCellValue(amt),
        ]);
      }
    }

    sheet.appendRow([
      xls.TextCellValue('GRAND TOTAL'),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.DoubleCellValue(_calculateGrandTotal()),
    ]);

    final encoded = excel.encode();
    if (encoded != null) {
      await widget.onSaveExcel(Uint8List.fromList(encoded), _fileNameCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel (.xlsx) Saved to Vault!')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Excel Ledger Studio'),
        actions: [
          IconButton(
            tooltip: 'Add Row',
            onPressed: () {
              setState(() {
                _rows.add({
                  'item': TextEditingController(),
                  'qty': TextEditingController(),
                  'rate': TextEditingController(),
                });
              });
            },
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Save .XLSX',
            onPressed: _exportXlsx,
            icon: const Icon(Icons.save_alt),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _fileNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Spreadsheet File Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.table_view),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _rows.length,
              itemBuilder: (_, i) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _rows[i]['item'],
                            decoration: const InputDecoration(labelText: 'Particulars'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _rows[i]['qty'],
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(labelText: 'Qty'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _rows[i]['rate'],
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(labelText: 'Rate'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 72,
                          child: Text(
                            _calculateRowAmount(i).toStringAsFixed(2),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF0F172A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'GRAND TOTAL',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  '₹ ${_calculateGrandTotal().toStringAsFixed(2)}',
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

// =============================================================================
// DIGITAL SIGNATURE PAD STUDIO
// =============================================================================
class SignaturePadStudio extends StatefulWidget {
  final Future<void> Function(Uint8List pdfBytes, String name) onSaveSignaturePdf;

  const SignaturePadStudio({super.key, required this.onSaveSignaturePdf});

  @override
  State<SignaturePadStudio> createState() => _SignaturePadStudioState();
}

class _SignaturePadStudioState extends State<SignaturePadStudio> {
  final List<Offset?> _points = [];
  final GlobalKey _repaintKey = GlobalKey();

  Future<void> _exportSignature() async {
    final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
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
              pw.Text('Authorized Digital Signature • AN Office'),
              pw.SizedBox(height: 20),
              pw.Image(pwImg, width: 300),
            ],
          ),
        ),
      ),
    );

    final outBytes = await pdf.save();
    await widget.onSaveSignaturePdf(
      outBytes,
      'Signature_${DateFormat('ddMMM_HHmm').format(DateTime.now())}',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signature Saved to Vault!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Signature Pad'),
        actions: [
          IconButton(
            tooltip: 'Clear Pad',
            onPressed: () => setState(() => _points.clear()),
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
          IconButton(
            tooltip: 'Save Signature PDF',
            onPressed: _exportSignature,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Sign inside the box below using your finger or stylus:'),
            const SizedBox(height: 12),
            Expanded(
              child: RepaintBoundary(
                key: _repaintKey,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF0F172A), width: 2),
                  ),
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      final box = context.findRenderObject() as RenderBox;
                      setState(() {
                        _points.add(box.globalToLocal(details.globalPosition));
                      });
                    },
                    onPanEnd: (_) => _points.add(null),
                    child: CustomPaint(
                      painter: _SignaturePainter(_points),
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

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  _SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
