import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Deep Slate Navy
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981), // Emerald Accent
          surface: Color(0xFF1E293B), // Card Slate
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
      ),
      home: const ScannerDashboardPage(),
    );
  }
}

class ScannedDocument {
  final File file;
  final String title;
  final String date;
  final String size;
  final String textFilePath;

  ScannedDocument({
    required this.file,
    required this.title,
    required this.date,
    required this.size,
    required this.textFilePath,
  });
}

class ScannerDashboardPage extends StatefulWidget {
  const ScannerDashboardPage({super.key});

  @override
  State<ScannerDashboardPage> createState() => _ScannerDashboardPageState();
}

class _ScannerDashboardPageState extends State<ScannerDashboardPage> {
  List<ScannedDocument> _documents = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final pdfFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList();

    List<ScannedDocument> loaded = [];
    for (var file in pdfFiles) {
      final stat = file.statSync();
      final sizeKb = (stat.size / 1024).toStringAsFixed(1);
      final dateStr =
          "${stat.modified.day}/${stat.modified.month}/${stat.modified.year}";
      final name = file.path.split('/').last.replaceAll('.pdf', '');
      final txtPath = file.path.replaceAll('.pdf', '.txt');

      loaded.add(ScannedDocument(
        file: file,
        title: name,
        date: dateStr,
        size: "$sizeKb KB",
        textFilePath: txtPath,
      ));
    }

    setState(() {
      _documents = loaded.reversed.toList();
    });
  }

  Future<String?> _promptFileName(String defaultPrefix) async {
    final defaultName =
        "${defaultPrefix}_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    final controller = TextEditingController(text: defaultName);

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Save Document',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Document Name',
              suffixText: '.pdf',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final text = controller.text.trim();
                Navigator.pop(context, text.isEmpty ? defaultName : text);
              },
              child: const Text('Save PDF'),
            ),
          ],
        );
      },
    );
  }

  Future<String> _extractTextFromImages(List<String> imagePaths) async {
    final textRecognizer =
        TextRecognizer(script: TextRecognitionScript.latin);
    StringBuffer fullExtractedText = StringBuffer();

    for (int i = 0; i < imagePaths.length; i++) {
      final inputImage = InputImage.fromFilePath(imagePaths[i]);
      final recognizedText = await textRecognizer.processImage(inputImage);
      if (imagePaths.length > 1) {
        fullExtractedText.writeln("--- Page ${i + 1} ---");
      }
      fullExtractedText.writeln(recognizedText.text);
      fullExtractedText.writeln();
    }

    await textRecognizer.close();
    return fullExtractedText.toString().trim();
  }

  // Multi-Page Document Scan with OCR
  Future<void> _startDocumentScan() async {
    try {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormat: DocumentFormat.jpeg,
          mode: ScannerMode.full, // Native preview with Original / Filter toggle
          isGalleryImport: true,
          pageLimit: 30,
        ),
      );

      final result = await scanner.scanDocument();
      await scanner.close();

      if (result.images.isNotEmpty) {
        final chosenName = await _promptFileName('AN_Doc');
        if (chosenName == null) return;

        setState(() => _isProcessing = true);

        // Run On-Device OCR
        final ocrText = await _extractTextFromImages(result.images);

        // Generate Crisp PDF
        final pdfDocument = pw.Document();
        for (final imgPath in result.images) {
          final bytes = await File(imgPath).readAsBytes();
          final imageProvider = pw.MemoryImage(bytes);
          pdfDocument.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: pw.EdgeInsets.zero,
              build: (context) => pw.Center(
                child: pw.Image(imageProvider, fit: pw.BoxFit.contain),
              ),
            ),
          );
        }

        final dir = await getApplicationDocumentsDirectory();
        final pdfFile = File('${dir.path}/$chosenName.pdf');
        await pdfFile.writeAsBytes(await pdfDocument.save());

        if (ocrText.isNotEmpty) {
          final txtFile = File('${dir.path}/$chosenName.txt');
          await txtFile.writeAsString(ocrText);
        }

        await _refreshFiles();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // ID Card (2-in-1 Stacked Layout) Mode
  Future<void> _startIdCardScan() async {
    try {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormat: DocumentFormat.jpeg,
          mode: ScannerMode.full,
          isGalleryImport: true,
          pageLimit: 2,
        ),
      );

      final result = await scanner.scanDocument();
      await scanner.close();

      if (result.images.isNotEmpty) {
        final chosenName = await _promptFileName('AN_IDCard');
        if (chosenName == null) return;

        setState(() => _isProcessing = true);

        final ocrText = await _extractTextFromImages(result.images);
        final pdfDocument = pw.Document();

        if (result.images.length == 1) {
          final bytes = await File(result.images[0]).readAsBytes();
          pdfDocument.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (context) => pw.Center(
                child: pw.Image(pw.MemoryImage(bytes), height: 350),
              ),
            ),
          );
        } else {
          // Stack 2 photos vertically (one above the other)
          final bytes1 = await File(result.images[0]).readAsBytes();
          final bytes2 = await File(result.images[1]).readAsBytes();

          pdfDocument.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(32),
              build: (context) {
                return pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      height: 310,
                      child: pw.Image(pw.MemoryImage(bytes1), fit: pw.BoxFit.contain),
                    ),
                    pw.Divider(thickness: 1, color: PdfColors.grey300),
                    pw.Container(
                      height: 310,
                      child: pw.Image(pw.MemoryImage(bytes2), fit: pw.BoxFit.contain),
                    ),
                  ],
                );
              },
            ),
          );
        }

        final dir = await getApplicationDocumentsDirectory();
        final pdfFile = File('${dir.path}/$chosenName.pdf');
        await pdfFile.writeAsBytes(await pdfDocument.save());

        if (ocrText.isNotEmpty) {
          final txtFile = File('${dir.path}/$chosenName.txt');
          await txtFile.writeAsString(ocrText);
        }

        await _refreshFiles();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ID Scan Error: $e')),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showOcrSheet(ScannedDocument doc) async {
    final txtFile = File(doc.textFilePath);
    String extracted = "No text detected in this document.";
    if (await txtFile.exists()) {
      extracted = await txtFile.readAsString();
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Extracted Text (OCR)',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Color(0xFF10B981)),
                        tooltip: 'Copy all text',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: extracted));
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Text copied to clipboard!')),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: SelectableText(
                        extracted,
                        style: const TextStyle(
                            fontSize: 15, height: 1.5, color: Color(0xFFE2E8F0)),
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
  }

  void _deleteDocument(ScannedDocument doc) async {
    if (await doc.file.exists()) await doc.file.delete();
    final txt = File(doc.textFilePath);
    if (await txt.exists()) await txt.delete();
    _refreshFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.document_scanner, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text('AN SCAN'),
          ],
        ),
      ),
      body: Stack(
        children: [
          _documents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 64, color: Colors.grey.shade600),
                      const SizedBox(height: 16),
                      const Text(
                        'No Scanned Documents',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose a capture mode below to start',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
                  itemCount: _documents.length,
                  itemBuilder: (context, index) {
                    final doc = _documents[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.06), width: 1),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.picture_as_pdf,
                              color: Colors.redAccent, size: 28),
                        ),
                        title: Text(
                          doc.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "${doc.date} • ${doc.size}",
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 13),
                          ),
                        ),
                        onTap: () => OpenFile.open(doc.file.path),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // OCR Button
                            IconButton(
                              icon: const Icon(Icons.text_fields,
                                  color: Color(0xFF10B981)),
                              tooltip: 'Extracted Text (OCR)',
                              onPressed: () => _showOcrSheet(doc),
                            ),
                            // Share Button
                            IconButton(
                              icon: const Icon(Icons.share_outlined,
                                  color: Colors.blueAccent),
                              tooltip: 'Share',
                              onPressed: () =>
                                  Share.shareXFiles([XFile(doc.file.path)]),
                            ),
                            // Delete Button
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.grey),
                              tooltip: 'Delete',
                              onPressed: () => _deleteDocument(doc),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF10B981)),
                    SizedBox(height: 16),
                    Text(
                      'Optimizing & Extracting Text...',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _startDocumentScan,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Doc Scan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _startIdCardScan,
                icon: const Icon(Icons.badge_outlined),
                label: const Text('ID Card (2-in-1)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF334155),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

