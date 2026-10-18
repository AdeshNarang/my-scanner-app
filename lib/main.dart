import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
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

void main() {
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
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF008080), // Classic Adobe Teal
          secondary: Color(0xFF0F172A),
          surface: Colors.white,
          onSurface: Color(0xFF0F172A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0.5,
        ),
      ),
      home: const ANHomeScreen(),
    );
  }
}

// Crisp Vector "AN" Monogram Logo
class ANLogoBadge extends StatelessWidget {
  final double size;
  const ANLogoBadge({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(size * 0.25),
        border: Border.all(color: const Color(0xFF008080), width: 1.5),
      ),
      child: Center(
        child: Text(
          'AN',
          style: TextStyle(
            color: const Color(0xFF2DD4BF),
            fontWeight: FontWeight.w900,
            fontSize: size * 0.44,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

class ScannedDocument {
  final File file;
  final String title;
  final DateTime modified;
  final String sizeMb;
  final List<String> pageImagePaths;
  final bool isIdCard;

  ScannedDocument({
    required this.file,
    required this.title,
    required this.modified,
    required this.sizeMb,
    required this.pageImagePaths,
    required this.isIdCard,
  });
}

class ANHomeScreen extends StatefulWidget {
  const ANHomeScreen({super.key});

  @override
  State<ANHomeScreen> createState() => _ANHomeScreenState();
}

class _ANHomeScreenState extends State<ANHomeScreen> with SingleTickerProviderStateMixin {
  List<ScannedDocument> _allDocs = [];
  String _searchQuery = '';
  late TabController _tabController;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final pdfFiles = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'))
          .toList();

      List<ScannedDocument> loaded = [];
      for (var file in pdfFiles) {
        final stat = file.statSync();
        final sizeMb = (stat.size / (1024 * 1024)).toStringAsFixed(2);
        final rawName = file.path.split('/').last.replaceAll('.pdf', '');
        final isId = rawName.startsWith('ID_');

        final metaFile = File(file.path.replaceAll('.pdf', '.meta'));
        List<String> pages = [];
        if (metaFile.existsSync()) {
          pages = metaFile.readAsLinesSync().where((p) => File(p).existsSync()).toList();
        }

        loaded.add(ScannedDocument(
          file: file,
          title: rawName,
          modified: stat.modified,
          sizeMb: '$sizeMb MB',
          pageImagePaths: pages,
          isIdCard: isId,
        ));
      }

      loaded.sort((a, b) => b.modified.compareTo(a.modified));
      if (mounted) setState(() => _allDocs = loaded);
    } catch (_) {}
  }

  // Robust Normalizer: Converts raw photos/HEIC to clean, standardized JPEG
  Future<String> _normalizeToStandardJpg(String inputPath, int index) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final targetPath = '${dir.path}/page_norm_${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
      final fileBytes = await File(inputPath).readAsBytes();

      final decoded = img.decodeImage(fileBytes);
      if (decoded != null) {
        final jpgBytes = img.encodeJpg(decoded, quality: 95);
        await File(targetPath).writeAsBytes(jpgBytes);
        return targetPath;
      }
    } catch (_) {}
    return inputPath;
  }

  // Opens Document Studio IMMEDIATELY after selecting or snapping
  void _openStudioWithImages(List<String> rawPaths, {required bool isIdMode}) async {
    if (rawPaths.isEmpty) return;

    List<String> cleanPaths = [];
    for (int i = 0; i < rawPaths.length; i++) {
      cleanPaths.add(await _normalizeToStandardJpg(rawPaths[i], i));
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ANPreSaveStudio(
          initialImages: cleanPaths,
          isIdMode: isIdMode,
          onSaved: _loadDocuments,
        ),
      ),
    );
  }

  Future<void> _startUltraHdCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 100);
      if (photo != null) {
        _openStudioWithImages([photo.path], isIdMode: false);
      }
    } catch (_) {}
  }

  Future<void> _importFromGallery() async {
    try {
      final List<XFile> photos = await _picker.pickMultiImage(imageQuality: 100);
      if (photos.isNotEmpty) {
        _openStudioWithImages(photos.map((e) => e.path).toList(), isIdMode: false);
      }
    } catch (_) {}
  }

  Future<void> _startMLScan({required bool isIdMode}) async {
    try {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormat: DocumentFormat.jpeg,
          mode: ScannerMode.full, // Native preview with "Original" filter option
          isGalleryImport: true,
          pageLimit: isIdMode ? 2 : 50,
        ),
      );

      final result = await scanner.scanDocument();
      await scanner.close();

      if (result.images.isNotEmpty) {
        _openStudioWithImages(result.images, isIdMode: isIdMode);
      }
    } catch (_) {}
  }

  void _showCaptureSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_enhance, color: Color(0xFF008080), size: 28),
                title: const Text('Ultra-HD Camera (Highest Clarity)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Stock sensor clarity with full ISP post-processing'),
                onTap: () {
                  Navigator.pop(context);
                  _startUltraHdCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner, color: Colors.blueAccent, size: 28),
                title: const Text('Auto-Crop Scanner', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Multi-page edge detection & perspective alignment'),
                onTap: () {
                  Navigator.pop(context);
                  _startMLScan(isIdMode: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.badge_outlined, color: Colors.orangeAccent, size: 28),
                title: const Text('ID Card (2-in-1 Stacked)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Snap front and back, stacks vertically on one sheet'),
                onTap: () {
                  Navigator.pop(context);
                  _startMLScan(isIdMode: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: Colors.green, size: 28),
                title: const Text('Import High-Res Photos (Gallery)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Directly convert multiple camera photos into PDF'),
                onTap: () {
                  Navigator.pop(context);
                  _importFromGallery();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- TIERED PDF COMPRESSION WITH SIZE ESTIMATES & QUALITY INFO ---
  void _showCompressDialog(ScannedDocument doc) {
    final currentBytes = doc.file.lengthSync();
    final currentMb = currentBytes / (1024 * 1024);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Compress PDF', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Original Size: ${currentMb.toStringAsFixed(2)} MB', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            _compressOptionCard(
              title: 'Low Compression',
              subtitle: 'Best Quality (Recommended for printing & fine text)',
              estimatedSize: '${(currentMb * 0.75).toStringAsFixed(2)} MB',
              onTap: () {
                Navigator.pop(context);
                _executeCompression(doc, quality: 85, scale: 0.9, suffix: 'LowComp');
              },
            ),
            const SizedBox(height: 8),
            _compressOptionCard(
              title: 'Medium Compression',
              subtitle: 'Good Quality (Ideal for email & WhatsApp sharing)',
              estimatedSize: '${(currentMb * 0.45).toStringAsFixed(2)} MB',
              onTap: () {
                Navigator.pop(context);
                _executeCompression(doc, quality: 60, scale: 0.7, suffix: 'MedComp');
              },
            ),
            const SizedBox(height: 8),
            _compressOptionCard(
              title: 'High Compression',
              subtitle: 'Smallest File Size (Reduced image clarity)',
              estimatedSize: '${(currentMb * 0.25).toStringAsFixed(2)} MB',
              onTap: () {
                Navigator.pop(context);
                _executeCompression(doc, quality: 35, scale: 0.5, suffix: 'HighComp');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _compressOptionCard({
    required String title,
    required String subtitle,
    required String estimatedSize,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF008080))),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFCCFBF1), borderRadius: BorderRadius.circular(4)),
              child: Text(estimatedSize, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF008080))),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeCompression(ScannedDocument doc, {required int quality, required double scale, required String suffix}) async {
    try {
      final pdfDoc = pw.Document();
      for (final p in doc.pageImagePaths) {
        final originalBytes = await File(p).readAsBytes();
        final decoded = img.decodeImage(originalBytes);
        if (decoded != null) {
          final resized = img.copyResize(decoded, width: (decoded.width * scale).round());
          final compressedBytes = img.encodeJpg(resized, quality: quality);
          pdfDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (context) => pw.Center(child: pw.Image(pw.MemoryImage(compressedBytes), fit: pw.BoxFit.contain)),
            ),
          );
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final compressedFile = File('${dir.path}/${doc.title}_$suffix.pdf');
      await compressedFile.writeAsBytes(await pdfDoc.save());
      await _loadDocuments();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF compressed and saved successfully!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compress failed: $e')));
    }
  }

  Future<void> _saveToDevice(ScannedDocument doc) async {
    try {
      Directory? downloadDir = Directory('/storage/emulated/0/Download/AN_Scan');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      final target = File('${downloadDir.path}/${doc.title}.pdf');
      await doc.file.copy(target.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to: Download/AN_Scan/${doc.title}.pdf')),
        );
      }
    } catch (e) {
      // Fallback to instant share if device permissions restrict raw path writes
      Share.shareXFiles([XFile(doc.file.path)], text: 'Export ${doc.title}');
    }
  }

  void _showAdobeActionSheet(ScannedDocument doc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.download_for_offline, color: Color(0xFF008080)),
                    title: const Text('Save to Device (Downloads)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    onTap: () {
                      Navigator.pop(context);
                      _saveToDevice(doc);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.share, color: Colors.blueAccent),
                    title: const Text('Share PDF'),
                    onTap: () {
                      Navigator.pop(context);
                      Share.shareXFiles([XFile(doc.file.path)]);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.compress, color: Colors.green),
                    title: const Text('Compress PDF (Choose Level)'),
                    onTap: () {
                      Navigator.pop(context);
                      _showCompressDialog(doc);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
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
    List<ScannedDocument> filtered = _allDocs.where((d) {
      final matchQuery = d.title.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchQuery) return false;
      if (_tabController.index == 1) return !d.isIdCard;
      if (_tabController.index == 2) return d.isIdCard;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: Colors.white,
        title: Row(
          children: const [
            ANLogoBadge(size: 34),
            SizedBox(width: 12),
            Text(
              'AN SCAN',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 19, color: Color(0xFF0F172A)),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(color: Color(0xFF0F172A)),
                    decoration: const InputDecoration(
                      hintText: 'Search scans...',
                      hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                      prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              TabBar(
                controller: _tabController,
                onTap: (_) => setState(() {}),
                labelColor: const Color(0xFF008080),
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: const Color(0xFF008080),
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'All Scans'),
                  Tab(text: 'Documents'),
                  Tab(text: 'ID Cards'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: filtered.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('No Scans Found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final doc = filtered[index];
                final dateStr = DateFormat('dd MMM yyyy • hh:mm a').format(doc.modified);
                final hasPreview = doc.pageImagePaths.isNotEmpty;

                return Card(
                  color: Colors.white,
                  elevation: 0.5,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ANPreSaveStudio(
                            initialImages: doc.pageImagePaths,
                            isIdMode: doc.isIdCard,
                            initialTitle: doc.title,
                            onSaved: _loadDocuments,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 62,
                              height: 80,
                              color: const Color(0xFFF1F5F9),
                              child: hasPreview
                                  ? Image.file(File(doc.pageImagePaths[0]), fit: BoxFit.cover)
                                  : const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 32),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doc.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF0F172A)),
                                ),
                                const SizedBox(height: 4),
                                Text(dateStr, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFCCFBF1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        doc.isIdCard ? 'ID CARD' : 'PDF',
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF008080)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(doc.sizeMb, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert, color: Colors.grey),
                            onPressed: () => _showAdobeActionSheet(doc),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF008080),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.camera_alt),
        label: const Text('Capture Scan', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _showCaptureSelector,
      ),
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<Offset?> points;
  final Color color;
  final double strokeWidth;

  DrawingPainter({required this.points, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => true;
}

// --- COMPLETE PRE-SAVE & POST-SAVE INTERACTIVE STUDIO ---
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
  late List<String> _pages;
  int _currentPage = 0;
  final PageController _pageController = PageController();

  List<Offset?> _drawPoints = [];
  bool _isCleanUpMode = false;
  bool _isDrawMode = false;

  String _customText = '';
  Offset _textPosition = const Offset(100, 150);
  double _fontSize = 20.0;
  Color _textColor = Colors.black;

  @override
  void initState() {
    super.initState();
    _pages = List.from(widget.initialImages);
  }

  Future<void> _runOcrForCurrentPage() async {
    if (_pages.isEmpty) return;
    try {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(_pages[_currentPage]);
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();

      final text = recognized.text.trim();

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return DraggableScrollableSheet(
            initialChildSize: 0.65,
            maxChildSize: 0.92,
            minChildSize: 0.4,
            expand: false,
            builder: (context, scrollCtrl) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Page ${_currentPage + 1} Digitize / OCR', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                        ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: text));
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied text to clipboard!')));
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy All'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollCtrl,
                        child: SelectableText(
                          text.isEmpty ? 'No readable English text detected on this page.' : text,
                          style: const TextStyle(fontSize: 15, height: 1.6, color: Color(0xFF1E293B)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCR Error: $e')));
    }
  }

  void _openTextDialog() {
    final controller = TextEditingController(text: _customText);
    double localSize = _fontSize;
    Color localColor = _textColor;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Add / Edit Text', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(hintText: 'Enter text...', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                const Text('Text Size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Slider(
                  value: localSize,
                  min: 12.0,
                  max: 48.0,
                  activeColor: const Color(0xFF008080),
                  onChanged: (val) => setDialogState(() => localSize = val),
                ),
                const SizedBox(height: 8),
                const Text('Text Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [Colors.black, Colors.white, Colors.red, Colors.blue, const Color(0xFF008080)].map((c) {
                    return GestureDetector(
                      onTap: () => setDialogState(() => localColor = c),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: localColor == c ? Colors.black : Colors.grey.shade400, width: 2),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _customText = '');
                Navigator.pop(context);
              },
              child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080)),
              onPressed: () {
                setState(() {
                  _customText = controller.text.trim();
                  _fontSize = localSize;
                  _textColor = localColor;
                });
                Navigator.pop(context);
              },
              child: const Text('Apply Text', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveFinalPdf() async {
    final titleController = TextEditingController(
      text: widget.initialTitle ?? 'Doc_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
    );

    final chosenName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Save PDF Document', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'File Name', suffixText: '.pdf', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080)),
            onPressed: () => Navigator.pop(context, titleController.text.trim()),
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (chosenName == null || chosenName.isEmpty) return;

    try {
      final pdfDoc = pw.Document();

      if (widget.isIdMode && _pages.length > 1) {
        final img1 = pw.MemoryImage(await File(_pages[0]).readAsBytes());
        final img2 = pw.MemoryImage(await File(_pages[1]).readAsBytes());
        pdfDoc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            build: (context) => pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: [
                pw.Container(height: 310, child: pw.Image(img1, fit: pw.BoxFit.contain)),
                pw.Divider(thickness: 1, color: PdfColors.grey400),
                pw.Container(height: 310, child: pw.Image(img2, fit: pw.BoxFit.contain)),
              ],
            ),
          ),
        );
      } else {
        for (final p in _pages) {
          final imgBytes = await File(p).readAsBytes();
          pdfDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: pw.EdgeInsets.zero,
              build: (context) => pw.Center(child: pw.Image(pw.MemoryImage(imgBytes), fit: pw.BoxFit.contain)),
            ),
          );
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final pdfFile = File('${dir.path}/$chosenName.pdf');
      await pdfFile.writeAsBytes(await pdfDoc.save());

      final metaFile = File('${dir.path}/$chosenName.meta');
      await metaFile.writeAsString(_pages.join('\n'));

      widget.onSaved();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document successfully saved!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save error: $e')));
    }
  }

  void _openPageManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ANPageOrganizerScreen(
          pagePaths: _pages,
          onPagesUpdated: (newPages) {
            setState(() {
              _pages = newPages;
              if (_currentPage >= _pages.length && _pages.isNotEmpty) {
                _currentPage = _pages.length - 1;
              }
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Document Studio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
            onPressed: _saveFinalPdf,
            child: const Text('Save PDF', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _pages.isEmpty
          ? const Center(child: Text('No pages available'))
          : LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    GestureDetector(
                      onPanUpdate: (_isCleanUpMode || _isDrawMode)
                          ? (details) => setState(() => _drawPoints.add(details.localPosition))
                          : null,
                      onPanEnd: (_isCleanUpMode || _isDrawMode) ? (_) => _drawPoints.add(null) : null,
                      child: PageView.builder(
                        controller: _pageController,
                        physics: (_isCleanUpMode || _isDrawMode) ? const NeverScrollableScrollPhysics() : null,
                        itemCount: _pages.length,
                        onPageChanged: (idx) => setState(() {
                          _currentPage = idx;
                          _drawPoints.clear();
                        }),
                        itemBuilder: (context, index) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Center(child: Image.file(File(_pages[index]), fit: BoxFit.contain)),
                              if (_drawPoints.isNotEmpty)
                                CustomPaint(
                                  painter: DrawingPainter(
                                    points: _drawPoints,
                                    color: _isCleanUpMode ? Colors.white : Colors.blueAccent,
                                    strokeWidth: _isCleanUpMode ? 20.0 : 3.5,
                                  ),
                                ),
                              if (_customText.isNotEmpty)
                                Positioned(
                                  left: _textPosition.dx.clamp(0.0, constraints.maxWidth - 100),
                                  top: _textPosition.dy.clamp(0.0, constraints.maxHeight - 50),
                                  child: GestureDetector(
                                    onPanUpdate: (details) {
                                      setState(() {
                                        _textPosition = Offset(
                                          _textPosition.dx + details.delta.dx,
                                          _textPosition.dy + details.delta.dy,
                                        );
                                      });
                                    },
                                    onDoubleTap: _openTextDialog,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.08),
                                        border: Border.all(color: const Color(0xFF008080), width: 1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _customText,
                                        style: TextStyle(
                                          color: _textColor,
                                          fontSize: _fontSize,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    Positioned(
                      top: 14,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                          child: Text('Page ${_currentPage + 1} of ${_pages.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: Icon(Icons.cleaning_services, color: _isCleanUpMode ? const Color(0xFF008080) : Colors.grey),
              tooltip: 'Clean-up (White-out)',
              onPressed: () => setState(() {
                _isCleanUpMode = !_isCleanUpMode;
                _isDrawMode = false;
              }),
            ),
            IconButton(
              icon: Icon(Icons.draw, color: _isDrawMode ? const Color(0xFF008080) : Colors.grey),
              tooltip: 'Draw / Annotate',
              onPressed: () => setState(() {
                _isDrawMode = !_isDrawMode;
                _isCleanUpMode = false;
              }),
            ),
            IconButton(
              icon: const Icon(Icons.text_fields, color: Colors.grey),
              tooltip: 'Type Text (Move/Resize/Color)',
              onPressed: _openTextDialog,
            ),
            IconButton(
              icon: const Icon(Icons.swap_horiz, color: Colors.grey),
              tooltip: 'Reorder / Rotate Pages',
              onPressed: _openPageManager,
            ),
            ElevatedButton.icon(
              onPressed: _pages.isNotEmpty ? _runOcrForCurrentPage : null,
              icon: const Icon(Icons.document_scanner, size: 16),
              label: const Text('OCR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF008080),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ANPageOrganizerScreen extends StatefulWidget {
  final List<String> pagePaths;
  final Function(List<String>) onPagesUpdated;

  const ANPageOrganizerScreen({super.key, required this.pagePaths, required this.onPagesUpdated});

  @override
  State<ANPageOrganizerScreen> createState() => _ANPageOrganizerScreenState();
}

class _ANPageOrganizerScreenState extends State<ANPageOrganizerScreen> {
  late List<String> _pages;

  @override
  void initState() {
    super.initState();
    _pages = List.from(widget.pagePaths);
  }

  Future<void> _rotatePage(int index) async {
    final path = _pages[index];
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      final rotated = img.copyRotate(decoded, angle: 90);
      await File(path).writeAsBytes(img.encodeJpg(rotated, quality: 95));
      setState(() {});
    }
  }

  void _deletePage(int index) {
    if (_pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document must have at least one page!')));
      return;
    }
    setState(() => _pages.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Reorder & Rotate Pages', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
            onPressed: () {
              widget.onPagesUpdated(_pages);
              Navigator.pop(context);
            },
            child: const Text('Apply Changes'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pages.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (oldIndex < newIndex) newIndex -= 1;
            final item = _pages.removeAt(oldIndex);
            _pages.insert(newIndex, item);
          });
        },
        itemBuilder: (context, index) {
          final path = _pages[index];
          return Card(
            key: ValueKey(path),
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(8),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(File(path), width: 50, height: 65, fit: BoxFit.cover),
              ),
              title: Text('Page ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Drag handle to reorder • Tap rotate for Portrait/Landscape'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.rotate_right, color: Color(0xFF008080)),
                    tooltip: 'Rotate 90°',
                    onPressed: () => _rotatePage(index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    tooltip: 'Delete Page',
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
