import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'models/document_models.dart';
import 'screens/ai_hub.dart';
import 'screens/compressor_screen.dart';
import 'screens/converter_screen.dart';
import 'screens/excel_studio.dart';
import 'screens/ocr_studio.dart';
import 'screens/pdf_reader.dart';
import 'screens/pdf_studio.dart';
import 'screens/word_studio.dart';
import 'services/converter_engine.dart';

const Color kNavyPrimary = Color(0xFF0F172A);
const Color kNavySecondary = Color(0xFF1E293B);
const Color kBlueAccent = Color(0xFF2563EB);
const Color kBlueLight = Color(0xFFDBEAFE);
const Color kStudioLightBg = Color(0xFFF8FAFC);
const Color kWhitePure = Colors.white;
const Color kBorderSubtle = Color(0xFFE2E8F0);
const Color kSlateMuted = Color(0xFF64748B);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const AnOfficeApp());
}

class AnOfficeApp extends StatelessWidget {
  const AnOfficeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AN Office PRO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kStudioLightBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBlueAccent,
          primary: kBlueAccent,
          surface: kWhitePure,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const MethodChannel _intentChannel = MethodChannel('com.adeshnarang.an_office/intent');
  List<FileSystemEntity> _vaultFiles = [];
  bool _loadingVault = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadVaultDocuments();
    _initIntentListener();
  }

  void _initIntentListener() {
    _intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onIncomingFile') {
        final filePath = call.arguments as String?;
        if (filePath != null && mounted) {
          _dispatchFileOpening(filePath);
        }
      }
    });

    _intentChannel.invokeMethod<String>('getInitialFile').then((filePath) {
      if (filePath != null && mounted) {
        _dispatchFileOpening(filePath);
      }
    });
  }

  Future<void> _loadVaultDocuments() async {
    setState(() => _loadingVault = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory(p.join(dir.path, 'vault'));
      if (!await vaultDir.exists()) {
        await vaultDir.create(recursive: true);
      }
      final files = vaultDir.listSync().where((f) {
        if (f is! File) return false;
        final name = f.path.toLowerCase();
        return name.endsWith('.pdf') ||
            name.endsWith('.docx') ||
            name.endsWith('.xlsx') ||
            name.endsWith('.xls') ||
            name.endsWith('.csv') ||
            name.endsWith('.tsv') ||
            name.endsWith('.txt') ||
            name.endsWith('.png') ||
            name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.webp');
      }).toList();

      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      if (mounted) {
        setState(() {
          _vaultFiles = files;
          _loadingVault = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingVault = false);
    }
  }

  Future<void> _saveFileToVault(String srcPath, String defaultName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory(p.join(dir.path, 'vault'));
      if (!await vaultDir.exists()) await vaultDir.create(recursive: true);

      final cleanName = defaultName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final targetPath = p.join(vaultDir.path, cleanName);
      await File(srcPath).copy(targetPath);
      await _loadVaultDocuments();
    } catch (_) {}
  }

  Future<void> _runCamScanner() async {
    try {
      final options = DocumentScannerOptions(
        documentFormats: [DocumentFormat.pdf, DocumentFormat.jpeg],
        mode: ScannerMode.full,
        isGalleryImport: true,
        pageLimit: 20,
      );
      final scanner = DocumentScanner(options: options);
      final result = await scanner.scanDocument();
      final pdfUri = result.pdf?.uri;
      final images = result.images;

      if (pdfUri != null && pdfUri.isNotEmpty) {
        final pdfPath = pdfUri.startsWith('file://') ? Uri.parse(pdfUri).toFilePath() : pdfUri;
        final fileName = 'CamScan_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await _saveFileToVault(pdfPath, fileName);
        if (mounted) _dispatchFileOpening(p.join((await getApplicationDocumentsDirectory()).path, 'vault', fileName));
      } else if (images.isNotEmpty) {
        final imgBytes = await File(images.first).readAsBytes();
        final pdfBytes = UniversalFormatConverterEngine.buildExcelBytes([]); // Fallback builder
        // Or route directly into PDF studio with scanned images
        final docPages = [
          EditableDocumentPage(originalBytes: imgBytes, displayBytes: imgBytes, imageWidth: 1200, imageHeight: 1600)
        ];
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AcrobatDocumentStudioScreen(
                initialPages: docPages,
                initialTitle: 'CamScan_${DateTime.now().millisecondsSinceEpoch}',
                defaultQuality: 90,
                ocrLang: OcrLanguageMode.english,
                onSaveDocument: (bytes, name) async {
                  final dir = await getApplicationDocumentsDirectory();
                  final vaultFile = File(p.join(dir.path, 'vault', '$name.pdf'));
                  await vaultFile.writeAsBytes(bytes);
                  await _loadVaultDocuments();
                },
              ),
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _pickAndOpenAnyDocument() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'doc', 'xlsx', 'xls', 'csv', 'tsv', 'txt', 'png', 'jpg', 'jpeg', 'webp', 'pptx'],
      );
      if (picked != null && picked.files.single.path != null) {
        final filePath = picked.files.single.path!;
        await _saveFileToVault(filePath, p.basename(filePath));
        _dispatchFileOpening(filePath);
      }
    } catch (_) {}
  }

  Future<void> _dispatchFileOpening(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    final fileName = p.basename(filePath);

    if (ext == '.pdf') {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TruePdfReaderScreen(
            filePath: filePath,
            fileName: fileName,
            defaultQuality: 90,
            ocrLang: OcrLanguageMode.english,
            onFileUpdated: _loadVaultDocuments,
          ),
        ),
      );
    } else if (['.xlsx', '.xls', '.csv', '.tsv', '.ods'].contains(ext)) {
      if (!mounted) return;
      final bytes = await File(filePath).readAsBytes();
      final rows = UniversalFormatConverterEngine.extractRowsFromExcelOrCsv(bytes, ext);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NativeExcelSpreadsheetStudio(
            initialRows: rows,
            fileName: fileName,
            onSaveSheet: (updatedRows, name) async {
              final newBytes = UniversalFormatConverterEngine.buildExcelBytes(updatedRows, sheetName: name);
              await File(filePath).writeAsBytes(newBytes);
              await _loadVaultDocuments();
            },
          ),
        ),
      );
    } else if (['.docx', '.doc', '.txt', '.odt'].contains(ext)) {
      if (!mounted) return;
      final bytes = await File(filePath).readAsBytes();
      final paragraphs = await UniversalFormatConverterEngine.extractLinesFromDocx(bytes);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NativeWordDocumentStudio(
            initialParagraphs: paragraphs,
            fileName: fileName,
            onSaveDoc: (updatedParas, name) async {
              final newBytes = UniversalFormatConverterEngine.buildDocxBytes(title: name, paragraphs: updatedParas);
              await File(filePath).writeAsBytes(newBytes);
              await _loadVaultDocuments();
            },
          ),
        ),
      );
    } else {
      // Images & WebP
      if (!mounted) return;
      final bytes = await File(filePath).readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      final docPages = [
        EditableDocumentPage(
          originalBytes: bytes,
          displayBytes: bytes,
          imageWidth: decoded.width,
          imageHeight: decoded.height,
        )
      ];
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AcrobatDocumentStudioScreen(
            initialPages: docPages,
            initialTitle: fileName.replaceAll(RegExp(r'\.[^.]+?$'), ''),
            defaultQuality: 90,
            ocrLang: OcrLanguageMode.english,
            onSaveDocument: (pdfBytes, name) async {
              final dir = await getApplicationDocumentsDirectory();
              final outPath = File(p.join(dir.path, 'vault', '$name.pdf'));
              await outPath.writeAsBytes(pdfBytes);
              await _loadVaultDocuments();
            },
          ),
        ),
      );
    }
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kWhitePure,
        title: const Text('Search Vault', style: TextStyle(fontWeight: FontWeight.w900, color: kNavyPrimary)),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Type file name...', border: OutlineInputBorder()),
          onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBlueAccent),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _syncGoogleDriveCloud() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Drive sync ready. Authorize SHA-1 in Google Cloud Console if OAuth pending.'),
        backgroundColor: kBlueAccent,
      ),
    );
  }

  Future<void> _mergeOrSplitPdfTool() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );
      if (picked != null && picked.files.isNotEmpty) {
        if (picked.files.length == 1 && picked.files.single.path != null) {
          // Splitter mode
          _dispatchFileOpening(picked.files.single.path!);
        } else {
          // Merger mode
          final pdf = pw.Document();
          for (final f in picked.files) {
            if (f.path != null) {
              final bytes = await File(f.path!).readAsBytes();
              final loadedDoc = pw.Document();
              // Read pages via printing raster
              await for (final raster in Printing.raster(bytes, dpi: 150)) {
                final png = await raster.toPng();
                pdf.addPage(
                  pw.Page(
                    pageFormat: PdfPageFormat.a4,
                    margin: pw.EdgeInsets.zero,
                    build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
                  ),
                );
              }
            }
          }
          final mergedBytes = await pdf.save();
          final dir = await getApplicationDocumentsDirectory();
          final outName = 'Merged_Document_${DateTime.now().millisecondsSinceEpoch}.pdf';
          final outPath = p.join(dir.path, 'vault', outName);
          await File(outPath).writeAsBytes(mergedBytes);
          await _loadVaultDocuments();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Successfully merged PDFs into Vault!'), backgroundColor: Color(0xFF15803D)),
            );
            _dispatchFileOpening(outPath);
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final filteredFiles = _searchQuery.isEmpty
        ? _vaultFiles
        : _vaultFiles.where((f) => p.basename(f.path).toLowerCase().contains(_searchQuery)).toList();

    return Scaffold(
      backgroundColor: kStudioLightBg,
      appBar: AppBar(
        backgroundColor: kWhitePure,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shape: const Border(bottom: BorderSide(color: kBorderSubtle)),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: kBlueAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/logo.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.description, color: kWhitePure, size: 18)),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'AN Office PRO',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: kNavyPrimary),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search Vault',
            icon: const Icon(Icons.search, color: kNavyPrimary),
            onPressed: _showSearchDialog,
          ),
          IconButton(
            tooltip: 'Google Drive Cloud Sync',
            icon: const Icon(Icons.cloud_sync_outlined, color: kBlueAccent),
            onPressed: _syncGoogleDriveCloud,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: kBlueAccent,
        onRefresh: _loadVaultDocuments,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Clean Status Banner with CamScanner & Open File buttons
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: kWhitePure,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorderSubtle),
                  boxShadow: const [BoxShadow(color: Colors.black05, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'AN Office Vault',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kNavyPrimary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: kBlueLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_vaultFiles.length} Docs',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kBlueAccent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: kBlueAccent,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _runCamScanner,
                            icon: const Icon(Icons.camera_alt_outlined, size: 18),
                            label: const Text('CamScanner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kNavyPrimary,
                              side: const BorderSide(color: kBorderSubtle),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _pickAndOpenAnyDocument,
                            icon: const Icon(Icons.folder_open_rounded, size: 18, color: kBlueAccent),
                            label: const Text('Open File', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'CORE TOOLS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: kSlateMuted, letterSpacing: 0.8),
              ),
              const SizedBox(height: 12),
              // Clean 2x3 Core Tools Grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
                children: [
                  _buildCoreToolCard(
                    icon: Icons.transform_rounded,
                    title: 'Format Converter',
                    subtitle: 'PDF ⇄ Word ⇄ Excel',
                    color: const Color(0xFF2563EB),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FormatConverterScreen())),
                  ),
                  _buildCoreToolCard(
                    icon: Icons.compress_rounded,
                    title: 'Compress Doc',
                    subtitle: 'Quality & size tuner',
                    color: const Color(0xFF15803D),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentCompressorScreen())),
                  ),
                  _buildCoreToolCard(
                    icon: Icons.menu_book_rounded,
                    title: 'Document Reader',
                    subtitle: 'All formats & editor',
                    color: const Color(0xFF7C3AED),
                    onTap: _pickAndOpenAnyDocument,
                  ),
                  _buildCoreToolCard(
                    icon: Icons.auto_awesome_rounded,
                    title: 'AI Studio Hub',
                    subtitle: 'Invoices & OCR tools',
                    color: const Color(0xFFD97706),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiStudioHubScreen())),
                  ),
                  _buildCoreToolCard(
                    icon: Icons.translate_rounded,
                    title: 'Trilingual OCR',
                    subtitle: 'English, Hindi, Punjabi',
                    color: const Color(0xFF0D9488),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrilingualOcrStudioScreen())),
                  ),
                  _buildCoreToolCard(
                    icon: Icons.call_merge_rounded,
                    title: 'PDF Merge & Split',
                    subtitle: 'Combine or extract pages',
                    color: const Color(0xFFE11D48),
                    onTap: _mergeOrSplitPdfTool,
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'RECENT VAULT DOCUMENTS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: kSlateMuted, letterSpacing: 0.8),
                  ),
                  TextButton(
                    onPressed: _loadVaultDocuments,
                    child: const Text('Refresh', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _loadingVault
                  ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: kBlueAccent)))
                  : filteredFiles.isEmpty
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: kWhitePure,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: kBorderSubtle),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.folder_off_outlined, size: 42, color: Colors.grey),
                              SizedBox(height: 10),
                              Text('No documents in vault yet', style: TextStyle(color: kNavyPrimary, fontWeight: FontWeight.bold)),
                              SizedBox(height: 4),
                              Text('Use CamScanner or Open File to add documents.', style: TextStyle(color: kSlateMuted, fontSize: 12), textAlign: TextAlign.center),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredFiles.length,
                          itemBuilder: (_, i) {
                            final file = File(filteredFiles[i].path);
                            final fileName = p.basename(file.path);
                            final ext = p.extension(fileName).toLowerCase();
                            final sizeBytes = file.lengthSync();
                            final sizeKb = (sizeBytes / 1024).toStringAsFixed(1);

                            IconData typeIcon = Icons.insert_drive_file_outlined;
                            Color iconColor = kBlueAccent;
                            if (ext == '.pdf') {
                              typeIcon = Icons.picture_as_pdf_rounded;
                              iconColor = Colors.red;
                            } else if (['.xlsx', '.xls', '.csv', '.tsv'].contains(ext)) {
                              typeIcon = Icons.table_chart_rounded;
                              iconColor = Colors.green;
                            } else if (['.docx', '.doc', '.txt'].contains(ext)) {
                              typeIcon = Icons.article_rounded;
                              iconColor = Colors.blue;
                            } else if (['.png', '.jpg', '.jpeg', '.webp'].contains(ext)) {
                              typeIcon = Icons.image_rounded;
                              iconColor = Colors.purple;
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: kWhitePure,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: kBorderSubtle),
                              ),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: iconColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(typeIcon, color: iconColor, size: 22),
                                ),
                                title: Text(
                                  fileName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: kNavyPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${ext.toUpperCase().replaceAll('.', '')} • $sizeKb KB',
                                  style: const TextStyle(fontSize: 11.5, color: kSlateMuted),
                                ),
                                trailing: PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 18, color: kSlateMuted),
                                  onSelected: (val) async {
                                    if (val == 'open') {
                                      _dispatchFileOpening(file.path);
                                    } else if (val == 'share') {
                                      Share.shareXFiles([XFile(file.path)]);
                                    } else if (val == 'delete') {
                                      await file.delete();
                                      _loadVaultDocuments();
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'open', child: Text('View & Edit')),
                                    PopupMenuItem(value: 'share', child: Text('Share')),
                                    PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                                onTap: () => _dispatchFileOpening(file.path),
                              ),
                            );
                          },
                        ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoreToolCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: kWhitePure,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: kNavyPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 10.5, color: kSlateMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
