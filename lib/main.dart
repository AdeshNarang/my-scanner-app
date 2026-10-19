import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ANScanApp());
}

class ANScanApp extends StatelessWidget {
  const ANScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AN Scan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          primary: const Color(0xFF0F172A),
          secondary: const Color(0xFFD4AF37),
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

  VaultFile({
    required this.name,
    required this.path,
    required this.ext,
    required this.modified,
    required this.sizeBytes,
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
  String _searchQuery = '';
  List<String> _accounts = ['Adesh Narang (Admin)', 'Head Office Desk', 'Personal Vault'];
  String _currentAccount = 'Adesh Narang (Admin)';
  String? _masterPin;
  bool _isVaultUnlocked = false;
  int _defaultCompression = 75;
  StreamSubscription? _intentSub;

  @override
  void initState() {
    super.initState();
    _initWorkspace();
    _initIntentListener();
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }

  void _initIntentListener() {
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      _handleSharedFiles(value);
    }, onError: (err) {});

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      _handleSharedFiles(value);
      ReceiveSharingIntent.instance.reset();
    });
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    final vaultDir = await _getAccountVaultDir();
    for (var file in files) {
      if (file.path.isNotEmpty) {
        final src = File(file.path);
        if (await src.exists()) {
          final dest = p.join(vaultDir.path, p.basename(file.path));
          await src.copy(dest);
        }
      }
    }
    await _reloadVault();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully imported file via Open With intent!')),
      );
    }
  }

  Future<void> _initWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _accounts = prefs.getStringList('user_accounts') ??
          ['Adesh Narang (Admin)', 'Head Office Desk', 'Personal Vault'];
      _currentAccount = prefs.getString('active_account') ?? _accounts.first;
      _masterPin = prefs.getString('master_pin');
      _defaultCompression = prefs.getInt('default_compression') ?? 75;
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
        if (['PDF', 'DOCX', 'XLSX', 'CSV', 'TXT', 'PNG', 'JPG'].contains(ext)) {
          loaded.add(
            VaultFile(
              name: name,
              path: e.path,
              ext: ext,
              modified: stat.modified,
              sizeBytes: stat.size,
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

  Future<void> _importExternalFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'xlsx', 'csv', 'txt', 'png', 'jpg'],
    );
    if (result != null && result.files.single.path != null) {
      final srcPath = result.files.single.path!;
      final vaultDir = await _getAccountVaultDir();
      final fileName = p.basename(srcPath);
      final destPath = p.join(vaultDir.path, fileName);
      await File(srcPath).copy(destPath);
      await _reloadVault();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $fileName into Vault!')),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _captureScan({bool gallery = false}) async {
    List<String> paths = [];
    final picker = ImagePicker();
    if (!gallery) {
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
        builder: (_) => ScanPreviewStudio(
          imagePaths: paths,
          compression: _defaultCompression,
          onSave: (pdfBytes, name) async {
            final dir = await _getAccountVaultDir();
            final clean = name.endsWith('.pdf') ? name : '$name.pdf';
            await File(p.join(dir.path, clean)).writeAsBytes(pdfBytes);
            await _reloadVault();
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // UNIVERSAL FORMAT CONVERTER HUB
  // ===========================================================================
  void _openConverterHub() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Universal Format Converter Hub', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ],
            ),
            const Text('Select a bidirectional conversion workflow:', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            const Divider(height: 24),
            Expanded(
              child: ListView(
                children: [
                  _converterTile(
                    icon: Icons.picture_as_pdf,
                    title: 'PDF to Image (JPG/PNG)',
                    sub: 'Extract PDF pages into standalone high-res images',
                    onTap: () async {
                      Navigator.pop(ctx);
                      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
                      if (res != null && res.files.single.path != null) {
                        final bytes = await File(res.files.single.path!).readAsBytes();
                        final vaultDir = await _getAccountVaultDir();
                        int pageNum = 1;
                        await for (final page in Printing.raster(bytes, dpi: 200)) {
                          final png = await page.toPng();
                          await File(p.join(vaultDir.path, 'Extracted_Page_$pageNum.jpg')).writeAsBytes(png);
                          pageNum++;
                        }
                        await _reloadVault();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF Pages Extracted to Images!')));
                      }
                    },
                  ),
                  _converterTile(
                    icon: Icons.image_outlined,
                    title: 'Image to PDF',
                    sub: 'Compile camera or gallery photos into secure PDF',
                    onTap: () {
                      Navigator.pop(ctx);
                      _captureScan(gallery: true);
                    },
                  ),
                  _converterTile(
                    icon: Icons.description_outlined,
                    title: 'PDF to Word (.docx)',
                    sub: 'Convert text-based PDF or OCR scan into editable Word document',
                    onTap: () async {
                      Navigator.pop(ctx);
                      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
                      if (res != null && res.files.single.path != null) {
                        final bytes = await File(res.files.single.path!).readAsBytes();
                        final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
                        final sb = StringBuffer();
                        int pCount = 1;
                        await for (final page in Printing.raster(bytes, dpi: 150)) {
                          final imgFile = File(p.join((await getTemporaryDirectory()).path, 'tmp_$pCount.png'));
                          await imgFile.writeAsBytes(await page.toPng());
                          final txt = await recognizer.processImage(InputImage.fromFilePath(imgFile.path));
                          sb.writeln(txt.text);
                          pCount++;
                        }
                        await recognizer.close();
                        final vaultDir = await _getAccountVaultDir();
                        final docxBytes = _createDocx(sb.toString());
                        await File(p.join(vaultDir.path, 'Converted_Document.docx')).writeAsBytes(docxBytes);
                        await _reloadVault();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Converted PDF to Word (.docx)!')));
                      }
                    },
                  ),
                  _converterTile(
                    icon: Icons.table_chart_outlined,
                    title: 'Excel / CSV to PDF',
                    sub: 'Render spreadsheet financial tables into professional PDF',
                    onTap: () async {
                      Navigator.pop(ctx);
                      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv']);
                      if (res != null && res.files.single.path != null) {
                        final bytes = await File(res.files.single.path!).readAsBytes();
                        final excel = xls.Excel.decodeBytes(bytes);
                        final pdf = pw.Document();
                        for (final table in excel.tables.keys) {
                          final sheet = excel.tables[table]!;
                          pdf.addPage(
                            pw.MultiPage(
                              build: (_) => [
                                pw.Header(level: 0, text: 'Spreadsheet Report: $table'),
                                pw.Table.fromTextArray(
                                  data: sheet.rows.map((row) => row.map((cell) => cell?.value?.toString() ?? '').toList()).toList(),
                                ),
                              ],
                            ),
                          );
                        }
                        final vaultDir = await _getAccountVaultDir();
                        await File(p.join(vaultDir.path, 'Spreadsheet_Report.pdf')).writeAsBytes(await pdf.save());
                        await _reloadVault();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel Converted to PDF Report!')));
                      }
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

  Widget _converterTile({required IconData icon, required String title, required String sub, required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0F172A)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 11.5)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }

  Uint8List _createDocx(String text) {
    final archive = Archive();
    const ct = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
    const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';
    final body = text.split('\n').map((l) => '<w:p><w:r><w:t>${const HtmlEscape().convert(l)}</w:t></w:r></w:p>').join();
    final doc = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$body</w:body></w:document>''';
    archive.addFile(ArchiveFile('[Content_Types].xml', ct.length, utf8.encode(ct)));
    archive.addFile(ArchiveFile('_rels/.rels', rels.length, utf8.encode(rels)));
    archive.addFile(ArchiveFile('word/document.xml', doc.length, utf8.encode(doc)));
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
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
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 56, color: Color(0xFF0F172A)),
                    const SizedBox(height: 12),
                    const Text('AN SCAN VAULT LOCKED', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: const InputDecoration(labelText: 'Enter 4-Digit Master PIN', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          if (pinCtrl.text.trim() == _masterPin) {
                            setState(() => _isVaultUnlocked = true);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
                          }
                        },
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Unlock Vault'),
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
            const Text('AN SCAN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 19)),
            Text('$_currentAccount • adeshnarang.in', style: const TextStyle(fontSize: 11, color: Color(0xFFD4AF37))),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Import External File',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _importExternalFile,
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
          _buildStudioDashboard(),
          _buildVaultTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_customize_outlined), label: 'Studio'),
          NavigationDestination(icon: Icon(Icons.folder_special_outlined), label: 'Vault'),
          NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: 'Accounts'),
        ],
      ),
    );
  }

  Widget _buildStudioDashboard() {
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
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
                ),
                child: const Text('AN', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 22, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AN Scan Document Studio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('${_vaultFiles.length} Vault Documents Stored Securely', style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text('EXECUTIVE SCANNER & CONVERTER TOOLS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF475569))),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            _toolTile(
              icon: Icons.camera_enhance_rounded,
              title: 'Camera Capture',
              sub: 'Scan & Build PDF',
              color: const Color(0xFF0F172A),
              onTap: () => _captureScan(gallery: false),
            ),
            _toolTile(
              icon: Icons.collections_outlined,
              title: 'Gallery to PDF',
              sub: 'Batch Import & Compress',
              color: const Color(0xFF1D4ED8),
              onTap: () => _captureScan(gallery: true),
            ),
            _toolTile(
              icon: Icons.folder_zip_outlined,
              title: 'Format Converter Hub',
              sub: 'PDF ⇄ Image ⇄ Word ⇄ Excel',
              color: const Color(0xFFB45309),
              onTap: _openConverterHub,
            ),
            _toolTile(
              icon: Icons.call_merge_rounded,
              title: 'Merge PDFs',
              sub: 'Combine Multiple PDFs',
              color: const Color(0xFFB91C1C),
              onTap: _openPdfMergerDialog,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('RECENT DOCUMENTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.800, color: Color(0xFF475569))),
            TextButton(onPressed: () => setState(() => _tabIndex = 1), child: const Text('View All')),
          ],
        ),
        if (_vaultFiles.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No documents scanned yet. Tap Camera Capture to start.')),
            ),
          )
        else
          ..._vaultFiles.take(5).map(_buildFileCard),
      ],
    );
  }

  Widget _toolTile({required IconData icon, required String title, required String sub, required Color color, required VoidCallback onTap}) {
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5), maxLines: 1),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)), maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVaultTab() {
    final filtered = _vaultFiles.where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search Vault documents...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No documents found in Vault.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
        onTap: () async {
          if (file.ext == 'PDF') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PdfEditorStudio(filePath: file.path, fileName: file.name),
              ),
            );
          } else {
            await OpenFilex.open(file.path);
          }
        },
        leading: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: badge.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Text(file.ext, style: TextStyle(color: badge, fontWeight: FontWeight.w900, fontSize: 10.5)),
        ),
        title: Text(file.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1),
        subtitle: Text('${_formatBytes(file.sizeBytes)} • ${DateFormat('dd MMM yyyy').format(file.modified)}', style: const TextStyle(fontSize: 11.5)),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'share') {
              await Share.shareXFiles([XFile(file.path)], text: file.name);
            } else if (action == 'delete') {
              await File(file.path).delete();
              await _reloadVault();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'share', child: Text('Share / Export')),
            PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }

  Future<void> _openPdfMergerDialog() async {
    final pdfs = _vaultFiles.where((f) => f.ext == 'PDF').toList();
    if (pdfs.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Need at least 2 PDFs in Vault to merge!')));
      return;
    }
    final Set<String> selected = {};
    final nameCtrl = TextEditingController(text: 'Merged_${DateFormat('ddMMM_HHmm').format(DateTime.now())}');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: const Text('Merge Multiple PDFs'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Merged PDF Name')),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: pdfs.length,
                    itemBuilder: (_, i) => CheckboxListTile(
                      value: selected.contains(pdfs[i].path),
                      title: Text(pdfs[i].name, maxLines: 1),
                      onChanged: (v) => setModal(() => v! ? selected.add(pdfs[i].path) : selected.remove(pdfs[i].path)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: selected.length < 2 ? null : () async {
                Navigator.pop(ctx);
                final merged = pw.Document();
                for (final path in selected) {
                  final raw = await File(path).readAsBytes();
                  await for (final page in Printing.raster(raw, dpi: 150)) {
                    final png = await page.toPng();
                    merged.addPage(pw.Page(build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(png)))));
                  }
                }
                final dir = await _getAccountVaultDir();
                await File(p.join(dir.path, '${nameCtrl.text.trim()}.pdf')).writeAsBytes(await merged.save());
                await _reloadVault();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDFs Merged Successfully!')));
              },
              child: const Text('Merge'),
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
            leading: const CircleAvatar(backgroundColor: Color(0xFF0F172A), foregroundColor: Color(0xFFD4AF37), child: Text('AN')),
            title: Text(_currentAccount, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Active Executive Workspace'),
          ),
        ),
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

class ScanPreviewStudio extends StatefulWidget {
  final List<String> imagePaths;
  final int compression;
  final Future<void> Function(Uint8List bytes, String name) onSave;

  const ScanPreviewStudio({super.key, required this.imagePaths, required this.compression, required this.onSave});

  @override
  State<ScanPreviewStudio> createState() => _ScanPreviewStudioState();
}

class _ScanPreviewStudioState extends State<ScanPreviewStudio> {
  late List<String> _paths;
  int _idx = 0;
  late int _quality;
  bool _saving = false;
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _paths = List.from(widget.imagePaths);
    _quality = widget.compression;
    _nameCtrl = TextEditingController(text: 'AN_Scan_${DateFormat('ddMMM_HHmm').format(DateTime.now())}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Page ${_idx + 1} of ${_paths.length}'),
        actions: [
          IconButton(
            tooltip: 'Remove Page',
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              setState(() {
                _paths.removeAt(_idx);
                if (_idx >= _paths.length && _idx > 0) _idx--;
              });
              if (_paths.isEmpty) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'PDF File Name', border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: PageView.builder(
              itemCount: _paths.length,
              onPageChanged: (i) => setState(() => _idx = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.all(12),
                child: Image.file(File(_paths[i]), fit: BoxFit.contain),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Compression:'),
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
                    onPressed: _saving ? null : () async {
                      setState(() => _saving = true);
                      final pdf = pw.Document();
                      for (final pth in _paths) {
                        final comp = await FlutterImageCompress.compressWithFile(pth, quality: _quality);
                        final bytes = comp ?? await File(pth).readAsBytes();
                        pdf.addPage(pw.Page(build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(bytes)))));
                      }
                      await widget.onSave(await pdf.save(), _nameCtrl.text.trim());
                      if (mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(_saving ? 'Saving PDF...' : 'Save PDF to Vault'),
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

class PdfEditorStudio extends StatefulWidget {
  final String filePath;
  final String fileName;

  const PdfEditorStudio({super.key, required this.filePath, required this.fileName});

  @override
  State<PdfEditorStudio> createState() => _PdfEditorStudioState();
}

class _PdfEditorStudioState extends State<PdfEditorStudio> {
  List<Uint8List> _pageImages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPdfPages();
  }

  Future<void> _loadPdfPages() async {
    setState(() => _loading = true);
    final bytes = await File(widget.filePath).readAsBytes();
    final List<Uint8List> imgs = [];
    await for (final page in Printing.raster(bytes, dpi: 150)) {
      imgs.add(await page.toPng());
    }
    setState(() {
      _pageImages = imgs;
      _loading = false;
    });
  }

  Future<void> _saveChanges() async {
    final pdf = pw.Document();
    for (final img in _pageImages) {
      pdf.addPage(pw.Page(build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(img)))));
    }
    await File(widget.filePath).writeAsBytes(await pdf.save());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF updated successfully!')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, maxLines: 1),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save Changes',
            onPressed: _loading ? null : _saveChanges,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pageImages.isEmpty
              ? const Center(child: Text('No pages found.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _pageImages.length,
                  itemBuilder: (_, i) => Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.between,
                            children: [
                              Text('Page ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () {
                                      setState(() => _pageImages.removeAt(i));
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(),
                          Image.memory(_pageImages[i]),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
