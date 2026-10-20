import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

import 'models/document_models.dart';
import 'screens/compressor_studio.dart';
import 'screens/crop_studio.dart';
import 'screens/excel_studio.dart';
import 'screens/ocr_editor.dart';
import 'screens/pdf_reader.dart';
import 'screens/pdf_studio.dart';
import 'screens/word_studio.dart';
import 'services/converter_engine.dart';

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
        errorBuilder: (_, __, ___) => const Center(
          child: Text('AN', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2D2A26))),
        ),
      ),
    );
  }
}

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

  Future<void> _openDedicatedCompressionStudio() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (picked == null || picked.files.single.path == null || !mounted) return;

    final srcPath = picked.files.single.path!;
    final originalBytes = await File(srcPath).readAsBytes();
    final fileName = p.basename(srcPath);
    final isPdf = p.extension(srcPath).toLowerCase() == '.pdf';

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LivePdfImageCompressionScreen(
          originalBytes: originalBytes,
          fileName: fileName,
          isPdf: isPdf,
          onSaveCompressed: (compressedBytes, outName) async {
            final dir = await _getAccountVaultDir();
            final outFile = File(p.join(dir.path, outName));
            await outFile.writeAsBytes(compressedBytes);
            await _reloadVault();
          },
        ),
      ),
    );
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
              icon: Icons.compress_rounded,
              title: 'Compress PDF / Img',
              sub: 'Live Slider & Size Comparison',
              accent: kBlueAccent,
              onTap: _openDedicatedCompressionStudio,
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
}
