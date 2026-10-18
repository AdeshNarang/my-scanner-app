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
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF008080), // Adobe Classic Teal
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
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    final dir = await getApplicationDocumentsDirectory();
    final pdfFiles = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.pdf')).toList();

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
  }

  Future<String?> _promptTextInput(String title, String label, String defaultValue) async {
    final controller = TextEditingController(text: defaultValue);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080)),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // --- FULL SENSOR ULTRA-HD CAPTURE (Hardware Camera Pipeline) ---
  Future<void> _startUltraHdCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100, // Maximum hardware clarity, uncompressed ISP output
      );

      if (photo != null) {
        await _processCapturedPhotos([photo.path], isIdMode: false, prefix: 'AN_UltraHD');
      }
    } catch (e) {
      if (!e.toString().contains('cancelled') && !e.toString().contains('Canceled')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ultra-HD Camera: $e')));
      }
    }
  }

  // --- GALLERY BATCH IMPORT (High-Res Photos) ---
  Future<void> _importFromGallery() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(imageQuality: 100);
      if (images.isNotEmpty) {
        await _processCapturedPhotos(images.map((e) => e.path).toList(), isIdMode: false, prefix: 'AN_Gallery');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import error: $e')));
    }
  }

  // --- STANDARD ML SCANNER (Auto Edge Detection Mode) ---
  Future<void> _startMLScan({required bool isIdMode}) async {
    try {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormat: DocumentFormat.jpeg,
          mode: ScannerMode.full,
          isGalleryImport: true,
          pageLimit: isIdMode ? 2 : 50,
        ),
      );

      final result = await scanner.scanDocument();
      await scanner.close();

      if (result.images.isNotEmpty) {
        await _processCapturedPhotos(result.images, isIdMode: isIdMode, prefix: isIdMode ? 'ID_Card' : 'Doc');
      }
    } catch (e) {
      if (!e.toString().contains('cancelled') && !e.toString().contains('Canceled')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan: $e')));
      }
    }
  }

  // --- HIGH-FIDELITY PDF BUILDER (Lossless DPI Preservation) ---
  Future<void> _processCapturedPhotos(List<String> rawPaths, {required bool isIdMode, required String prefix}) async {
    final chosenName = await _promptTextInput(
      'Save Document',
      'File Name',
      '${prefix}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
    );
    if (chosenName == null || chosenName.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final dir = await getApplicationDocumentsDirectory();
      List<String> persistentPages = [];

      for (int i = 0; i < rawPaths.length; i++) {
        final dest = '${dir.path}/${chosenName}_page_$i.jpg';
        await File(rawPaths[i]).copy(dest);
        persistentPages.add(dest);
      }

      final pdfDoc = pw.Document();

      if (isIdMode && persistentPages.length > 1) {
        final img1 = pw.MemoryImage(await File(persistentPages[0]).readAsBytes());
        final img2 = pw.MemoryImage(await File(persistentPages[1]).readAsBytes());
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
        // Embed raw, uncompressed bytes into standard A4 containers to preserve original DPI
        for (final path in persistentPages) {
          final imgBytes = await File(path).readAsBytes();
          final imageProvider = pw.MemoryImage(imgBytes);
          pdfDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: pw.EdgeInsets.zero,
              build: (context) => pw.Center(
                child: pw.Image(imageProvider, fit: pw.BoxFit.contain),
              ),
            ),
          );
        }
      }

      final pdfFile = File('${dir.path}/$chosenName.pdf');
      await pdfFile.writeAsBytes(await pdfDoc.save());

      final metaFile = File('${dir.path}/$chosenName.meta');
      await metaFile.writeAsString(persistentPages.join('\n'));

      await _loadDocuments();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save error: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _compressPdf(ScannedDocument doc) async {
    setState(() => _isProcessing = true);
    try {
      final pdfDoc = pw.Document();
      for (final p in doc.pageImagePaths) {
        final originalBytes = await File(p).readAsBytes();
        final decoded = img.decodeImage(originalBytes);
        if (decoded != null) {
          final resized = img.copyResize(decoded, width: (decoded.width * 0.7).round());
          final compressedBytes = img.encodeJpg(resized, quality: 65);
          pdfDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (context) => pw.Center(child: pw.Image(pw.MemoryImage(compressedBytes), fit: pw.BoxFit.contain)),
            ),
          );
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final compressedFile = File('${dir.path}/${doc.title}_Compressed.pdf');
      await compressedFile.writeAsBytes(await pdfDoc.save());
      await _loadDocuments();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document successfully compressed!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compress failed: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Device save error: $e')));
    }
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
                title: const Text('Ultra-HD Camera (Maximum Quality)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Direct full-sensor capture with stock phone ISP & HDR'),
                onTap: () {
                  Navigator.pop(context);
                  _startUltraHdCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner, color: Colors.blueAccent, size: 28),
                title: const Text('Quick Auto-Crop Scanner', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Multi-page edge detection & perspective flattening'),
                onTap: () {
                  Navigator.pop(context);
                  _startMLScan(isIdMode: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.badge_outlined, color: Colors.orangeAccent, size: 28),
                title: const Text('ID Card (2-in-1 Stacked)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Front & back stacked cleanly on one single A4 page'),
                onTap: () {
                  Navigator.pop(context);
                  _startMLScan(isIdMode: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: Colors.green, size: 28),
                title: const Text('Import High-Res Photos (Gallery)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Convert high-resolution camera photos to PDF'),
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
                    leading: const Icon(Icons.edit_document, color: Color(0xFF008080)),
                    title: const Text('Open Interactive Document Editor', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    subtitle: const Text('Live text selection, reorder, rotate & markup'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ANDocumentViewer(document: doc, onUpdated: _loadDocuments)));
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
                    title: const Text('Compress PDF (Reduce Size)'),
                    onTap: () {
                      Navigator.pop(context);
                      _compressPdf(doc);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                    onTap: () {
                      Navigator.pop(context);
                      _deleteDoc(doc);
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

  void _deleteDoc(ScannedDocument doc) async {
    if (await doc.file.exists()) await doc.file.delete();
    final meta = File(doc.file.path.replaceAll('.pdf', '.meta'));
    if (await meta.exists()) await meta.delete();
    _loadDocuments();
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
                        MaterialPageRoute(builder: (_) => ANDocumentViewer(document: doc, onUpdated: _loadDocuments)),
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

// Custom Painter for Signatures & Markups
class SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  final Color color;
  final double strokeWidth;

  SignaturePainter({required this.points, this.color = Colors.black, this.strokeWidth = 3.0});

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
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}

// --- INTERACTIVE IN-DOCUMENT EDITOR WITH LIVE IN-IMAGE TEXT SELECTION ---
class ANDocumentViewer extends StatefulWidget {
  final ScannedDocument document;
  final VoidCallback onUpdated;
  const ANDocumentViewer({super.key, required this.document, required this.onUpdated});

  @override
  State<ANDocumentViewer> createState() => _ANDocumentViewerState();
}

class _ANDocumentViewerState extends State<ANDocumentViewer> {
  int _currentPage = 0;
  final PageController _pageController = PageController();
  List<String> _currentPages = [];
  List<Offset?> _drawPoints = [];
  bool _isCleanUpMode = false;
  bool _isDrawMode = false;
  String _typedText = '';
  List<TextLine> _liveTextLines = [];
  Size _imageSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _currentPages = List.from(widget.document.pageImagePaths);
    _extractLiveTextForCurrentPage();
  }

  Future<void> _extractLiveTextForCurrentPage() async {
    if (_currentPages.isEmpty) return;
    try {
      final imagePath = _currentPages[_currentPage];
      final decoded = await decodeImageFromList(await File(imagePath).readAsBytes());
      _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();

      List<TextLine> lines = [];
      for (var block in recognized.blocks) {
        lines.addAll(block.lines);
      }

      if (mounted) {
        setState(() {
          _liveTextLines = lines;
        });
      }
    } catch (_) {}
  }

  void _addTextOverlay() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Add Text with Keyboard'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter text to place on page...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080)),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (text != null && text.isNotEmpty) {
      setState(() => _typedText = text);
    }
  }

  void _openPageManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ANPageOrganizerScreen(
          pagePaths: _currentPages,
          onPagesUpdated: (newPages) async {
            setState(() {
              _currentPages = newPages;
              if (_currentPage >= _currentPages.length && _currentPages.isNotEmpty) {
                _currentPage = _currentPages.length - 1;
              }
            });

            final pdfDoc = pw.Document();
            for (final path in _currentPages) {
              final imgBytes = await File(path).readAsBytes();
              pdfDoc.addPage(
                pw.Page(
                  pageFormat: PdfPageFormat.a4,
                  margin: pw.EdgeInsets.zero,
                  build: (context) => pw.Center(child: pw.Image(pw.MemoryImage(imgBytes), fit: pw.BoxFit.contain)),
                ),
              );
            }
            await widget.document.file.writeAsBytes(await pdfDoc.save());

            final metaFile = File(widget.document.file.path.replaceAll('.pdf', '.meta'));
            await metaFile.writeAsString(_currentPages.join('\n'));

            widget.onUpdated();
            _extractLiveTextForCurrentPage();
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
        title: Text(widget.document.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF0F172A))),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_view_rounded, color: Color(0xFF008080)),
            tooltip: 'Reorder, Rotate & Resize Pages',
            onPressed: _openPageManager,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Share.shareXFiles([XFile(widget.document.file.path)]),
          ),
        ],
      ),
      body: _currentPages.isEmpty
          ? Center(child: Text('No page previews found', style: TextStyle(color: Colors.grey.shade600)))
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
                        itemCount: _currentPages.length,
                        onPageChanged: (idx) {
                          setState(() {
                            _currentPage = idx;
                            _drawPoints.clear();
                            _typedText = '';
                          });
                          _extractLiveTextForCurrentPage();
                        },
                        itemBuilder: (context, index) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Center(child: Image.file(File(_currentPages[index]), fit: BoxFit.contain)),
                              if (!_isCleanUpMode && !_isDrawMode && _imageSize != Size.zero)
                                _buildLiveTextOverlay(constraints.maxWidth, constraints.maxHeight),
                              if (_drawPoints.isNotEmpty)
                                CustomPaint(
                                  painter: SignaturePainter(
                                    points: _drawPoints,
                                    color: _isCleanUpMode ? Colors.white : Colors.blueAccent,
                                    strokeWidth: _isCleanUpMode ? 14.0 : 3.0,
                                  ),
                                ),
                              if (_typedText.isNotEmpty)
                                Positioned(
                                  top: 100,
                                  left: 40,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    color: Colors.yellow.withOpacity(0.85),
                                    child: Text(_typedText, style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
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
                          child: Text('Page ${_currentPage + 1} of ${_currentPages.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
              tooltip: 'Cleanup / White-out',
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
              tooltip: 'Type Text',
              onPressed: _addTextOverlay,
            ),
            ElevatedButton.icon(
              onPressed: _openPageManager,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Reorder & Rotate'),
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

  Widget _buildLiveTextOverlay(double screenW, double screenH) {
    if (_imageSize.width == 0 || _imageSize.height == 0) return const SizedBox.shrink();

    final scaleX = screenW / _imageSize.width;
    final scaleY = screenH / _imageSize.height;
    final scale = min(scaleX, scaleY);

    final renderedW = _imageSize.width * scale;
    final renderedH = _imageSize.height * scale;
    final offsetX = (screenW - renderedW) / 2;
    final offsetY = (screenH - renderedH) / 2;

    return Stack(
      children: _liveTextLines.map((line) {
        final box = line.boundingBox;
        final left = offsetX + (box.left * scale);
        final top = offsetY + (box.top * scale);
        final width = max(30.0, box.width * scale);
        final height = max(18.0, box.height * scale);

        return Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: SelectableText(
            line.text,
            style: TextStyle(
              fontSize: max(10.0, height * 0.75),
              color: Colors.transparent,
              backgroundColor: Colors.teal.withOpacity(0.04),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// --- FULL-PAGE MANAGEMENT SCREEN: REORDER, ROTATE & RESIZE ---
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
    setState(() {
      _pages.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Reorder & Resize Pages', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080), foregroundColor: Colors.white),
            onPressed: () {
              widget.onPagesUpdated(_pages);
              Navigator.pop(context);
            },
            child: const Text('Save & Update PDF'),
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
              subtitle: const Text('Drag to reorder • Tap rotate for Portrait/Landscape'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.rotate_right, color: Color(0xFF008080)),
                    tooltip: 'Rotate 90° (Portrait / Landscape)',
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
