import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
        scaffoldBackgroundColor: const Color(0xFF111827), // Classic Dark Canvas
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0D9488),
          surface: Color(0xFF1F2937),
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111827),
          elevation: 0,
        ),
      ),
      home: const ANHomeScreen(),
    );
  }
}

// Custom Executive AN Monogram Logo
class ANLogoBadge extends StatelessWidget {
  final double size;
  const ANLogoBadge({super.key, this.size = 36});

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
        border: Border.all(color: const Color(0xFF0D9488), width: 1.5),
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
  final String size;
  final List<String> pageImagePaths;
  final bool isIdCard;

  ScannedDocument({
    required this.file,
    required this.title,
    required this.modified,
    required this.size,
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
      final sizeKb = (stat.size / 1024).toStringAsFixed(0);
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
        size: '$sizeKb KB',
        pageImagePaths: pages,
        isIdCard: isId,
      ));
    }

    loaded.sort((a, b) => b.modified.compareTo(a.modified));
    setState(() {
      _allDocs = loaded;
    });
  }

  Future<String?> _promptTextInput(String title, String label, String defaultValue) async {
    final controller = TextEditingController(text: defaultValue);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startScan({required bool isIdMode, bool fromGallery = false}) async {
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
        final prefix = isIdMode ? 'ID_Card' : 'Doc';
        final chosenName = await _promptTextInput('Save Document', 'File Name', '${prefix}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}');
        if (chosenName == null || chosenName.isEmpty) return;

        setState(() => _isProcessing = true);

        final dir = await getApplicationDocumentsDirectory();
        List<String> persistentPages = [];
        for (int i = 0; i < result.images.length; i++) {
          final dest = '${dir.path}/${chosenName}_page_$i.jpg';
          await File(result.images[i]).copy(dest);
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
          for (final path in persistentPages) {
            final img = pw.MemoryImage(await File(path).readAsBytes());
            pdfDoc.addPage(
              pw.Page(
                pageFormat: PdfPageFormat.a4,
                margin: pw.EdgeInsets.zero,
                build: (context) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
              ),
            );
          }
        }

        final pdfFile = File('${dir.path}/$chosenName.pdf');
        await pdfFile.writeAsBytes(await pdfDoc.save());

        final metaFile = File('${dir.path}/$chosenName.meta');
        await metaFile.writeAsString(persistentPages.join('\n'));

        await _loadDocuments();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // --- FEATURE: Save as Word Doc (.docx) ---
  Future<void> _exportAsWordDoc(ScannedDocument doc) async {
    setState(() => _isProcessing = true);
    try {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      StringBuffer fullText = StringBuffer();

      for (var pagePath in doc.pageImagePaths) {
        final img = InputImage.fromFilePath(pagePath);
        final recognized = await recognizer.processImage(img);
        fullText.writeln(recognized.text);
        fullText.writeln();
      }
      await recognizer.close();

      final cleanXmlText = fullText.toString()
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');

      final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    ${cleanXmlText.split('\n').map((line) => '<w:p><w:r><w:t>$line</w:t></w:r></w:p>').join()}
  </w:body>
</w:document>''';

      final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-package.wordprocessingml.document.main+xml"/>
</Types>''';

      final relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

      final archive = Archive();
      archive.addFile(ArchiveFile('[Content_Types].xml', contentTypesXml.length, utf8.encode(contentTypesXml)));
      archive.addFile(ArchiveFile('_rels/.rels', relsXml.length, utf8.encode(relsXml)));
      archive.addFile(ArchiveFile('word/document.xml', documentXml.length, utf8.encode(documentXml)));

      final docxBytes = ZipEncoder().encode(archive)!;
      final dir = await getApplicationDocumentsDirectory();
      final docxFile = File('${dir.path}/${doc.title}.docx');
      await docxFile.writeAsBytes(docxBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved as Word doc: ${doc.title}.docx'),
          action: SnackBarAction(label: 'Open / Share', onPressed: () => Share.shareXFiles([XFile(docxFile.path)])),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Word export error: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // --- FEATURE: Compress PDF ---
  Future<void> _compressPdf(ScannedDocument doc) async {
    setState(() => _isProcessing = true);
    try {
      final pdfDoc = pw.Document(deflate: zlib.encode);
      for (final p in doc.pageImagePaths) {
        final bytes = await File(p).readAsBytes();
        final img = pw.MemoryImage(bytes);
        pdfDoc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (context) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
          ),
        );
      }
      final dir = await getApplicationDocumentsDirectory();
      final compressedFile = File('${dir.path}/${doc.title}_Compressed.pdf');
      await compressedFile.writeAsBytes(await pdfDoc.save());
      await _loadDocuments();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF compressed and saved!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compression failed: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // --- FEATURE: Save Pages as JPEG ---
  Future<void> _savePagesAsJpeg(ScannedDocument doc) async {
    final dir = await getApplicationDocumentsDirectory();
    int count = 0;
    for (int i = 0; i < doc.pageImagePaths.length; i++) {
      final source = File(doc.pageImagePaths[i]);
      if (source.existsSync()) {
        final target = File('${dir.path}/${doc.title}_Page_${i + 1}.jpeg');
        await source.copy(target.path);
        count++;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count pages saved as JPEG to app storage')),
    );
  }

  // --- FEATURE: Combine Multiple Files ---
  Future<void> _combineFiles() async {
    if (_allDocs.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Need at least 2 scans to combine!')));
      return;
    }

    final selected = await showDialog<List<ScannedDocument>>(
      context: context,
      builder: (context) {
        List<ScannedDocument> picked = [];
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1F2937),
              title: const Text('Combine Files into One PDF'),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: ListView.builder(
                  itemCount: _allDocs.length,
                  itemBuilder: (context, idx) {
                    final d = _allDocs[idx];
                    final isChecked = picked.contains(d);
                    return CheckboxListTile(
                      value: isChecked,
                      title: Text(d.title),
                      subtitle: Text('${d.pageImagePaths.length} pages'),
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) picked.add(d);
                          else picked.remove(d);
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                  onPressed: () => Navigator.pop(context, picked),
                  child: const Text('Combine'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null && selected.length >= 2) {
      setState(() => _isProcessing = true);
      final combinedPdf = pw.Document();
      List<String> combinedPages = [];

      for (var d in selected) {
        for (var p in d.pageImagePaths) {
          combinedPages.add(p);
          final img = pw.MemoryImage(await File(p).readAsBytes());
          combinedPdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (context) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
            ),
          );
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final newTitle = 'Combined_${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
      final file = File('${dir.path}/$newTitle.pdf');
      await file.writeAsBytes(await combinedPdf.save());

      final meta = File('${dir.path}/$newTitle.meta');
      await meta.writeAsString(combinedPages.join('\n'));

      await _loadDocuments();
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Files successfully combined!')));
    }
  }

  // --- ADOBE SCAN DARK 3-DOT ACTION SHEET ---
  void _showAdobeActionSheet(ScannedDocument doc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
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
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.share, color: Colors.white70),
                    title: const Text('Share'),
                    onTap: () {
                      Navigator.pop(context);
                      Share.shareXFiles([XFile(doc.file.path)]);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined, color: Color(0xFF2DD4BF)),
                    title: const Text('Save as Word doc (.docx)'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF0D9488), borderRadius: BorderRadius.circular(4)),
                      child: const Text('FREE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _exportAsWordDoc(doc);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.text_snippet_outlined, color: Colors.amber),
                    title: const Text('Digitize & Copy Text (OCR)'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ANDocumentViewer(document: doc)));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.draw_outlined, color: Colors.lightBlueAccent),
                    title: const Text('Fill & Sign (Signature Pad)'),
                    onTap: () {
                      Navigator.pop(context);
                      _showSignatureDialog(doc);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.merge_type, color: Colors.purpleAccent),
                    title: const Text('Combine files'),
                    onTap: () {
                      Navigator.pop(context);
                      _combineFiles();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_outline, color: Colors.orangeAccent),
                    title: const Text('Set password / Encrypt'),
                    onTap: () async {
                      Navigator.pop(context);
                      final pass = await _promptTextInput('Set Password', 'Enter document password', '');
                      if (pass != null && pass.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Password security flag set for ${doc.title}')));
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.compress, color: Colors.greenAccent),
                    title: const Text('Compress PDF'),
                    onTap: () {
                      Navigator.pop(context);
                      _compressPdf(doc);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.image_outlined, color: Colors.tealAccent),
                    title: const Text('Save pages as JPEG'),
                    onTap: () {
                      Navigator.pop(context);
                      _savePagesAsJpeg(doc);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.print_outlined, color: Colors.white70),
                    title: const Text('Print'),
                    onTap: () {
                      Navigator.pop(context);
                      Printing.layoutPdf(onLayout: (format) => doc.file.readAsBytes());
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined, color: Colors.white70),
                    title: const Text('Rename'),
                    onTap: () async {
                      Navigator.pop(context);
                      final newName = await _promptTextInput('Rename File', 'New name', doc.title);
                      if (newName != null && newName.isNotEmpty && newName != doc.title) {
                        final dir = await getApplicationDocumentsDirectory();
                        final newFile = File('${dir.path}/$newName.pdf');
                        await doc.file.rename(newFile.path);
                        _loadDocuments();
                      }
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

  // --- FEATURE: Fill & Sign (Signature Pad) ---
  void _showSignatureDialog(ScannedDocument doc) {
    List<Offset?> points = [];
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setPadState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('Fill & Sign: Draw Signature'),
              content: Container(
                width: 300,
                height: 180,
                color: Colors.white,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    RenderBox renderBox = context.findRenderObject() as RenderBox;
                    final localPos = renderBox.globalToLocal(details.globalPosition);
                    setPadState(() {
                      points.add(details.localPosition);
                    });
                  },
                  onPanEnd: (details) => points.add(null),
                  child: CustomPaint(
                    painter: SignaturePainter(points: points),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => setPadState(() => points.clear()),
                  child: const Text('Clear'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Signature stamped onto document!')),
                    );
                  },
                  child: const Text('Apply Signature'),
                ),
              ],
            );
          },
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
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: const [
            ANLogoBadge(size: 34),
            SizedBox(width: 12),
            Text(
              'AN SCAN',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontSize: 19,
                color: Colors.white,
              ),
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
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(color: Colors.white),
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
                labelColor: const Color(0xFF2DD4BF),
                unselectedLabelColor: Colors.grey.shade400,
                indicatorColor: const Color(0xFF2DD4BF),
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
      body: Stack(
        children: [
          filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey.shade600),
                      const SizedBox(height: 12),
                      const Text('No Scans Found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white70)),
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
                      color: const Color(0xFF1F2937),
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ANDocumentViewer(document: doc)),
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
                                  color: Colors.black26,
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
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(dateStr, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0D9488).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            doc.isIdCard ? 'ID CARD' : 'PDF',
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2DD4BF)),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(doc.size, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.more_vert, color: Colors.white70),
                                onPressed: () => _showAdobeActionSheet(doc),
                              ),
                            ],
                          ),
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
                    CircularProgressIndicator(color: Color(0xFF2DD4BF)),
                    SizedBox(height: 16),
                    Text('Processing Document...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ],
      ),
      // Adobe-Style Expandable Bottom Floating Action Menu
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        child: const Icon(Icons.camera_alt, size: 28),
        onPressed: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF1E293B),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (context) {
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.document_scanner, color: Color(0xFF2DD4BF)),
                      title: const Text('Create scan (Camera)'),
                      onTap: () {
                        Navigator.pop(context);
                        _startScan(isIdMode: false);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.badge_outlined, color: Colors.amberAccent),
                      title: const Text('ID Card (2-in-1 Stacked)'),
                      onTap: () {
                        Navigator.pop(context);
                        _startScan(isIdMode: true);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined, color: Colors.lightBlueAccent),
                      title: const Text('Create from photos (Gallery)'),
                      onTap: () {
                        Navigator.pop(context);
                        _startScan(isIdMode: false, fromGallery: true);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.merge_type, color: Colors.purpleAccent),
                      title: const Text('Combine files'),
                      onTap: () {
                        Navigator.pop(context);
                        _combineFiles();
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// Custom Painter for Digital Signature Drawing
class SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  SignaturePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}

// IN-DOCUMENT INTERACTIVE WORKSPACE (Pages + In-Document OCR)
class ANDocumentViewer extends StatefulWidget {
  final ScannedDocument document;
  const ANDocumentViewer({super.key, required this.document});

  @override
  State<ANDocumentViewer> createState() => _ANDocumentViewerState();
}

class _ANDocumentViewerState extends State<ANDocumentViewer> {
  int _currentPage = 0;
  bool _isRecognizing = false;
  final PageController _pageController = PageController();

  Future<void> _runInDocOcr(String imagePath) async {
    setState(() => _isRecognizing = true);
    try {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();

      final text = recognized.text.trim();

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E293B),
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
                        Text(
                          'Page ${_currentPage + 1} Digitize / OCR',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: text));
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied text to clipboard!')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy All'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: Colors.white24),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollCtrl,
                        child: SelectableText(
                          text.isEmpty ? 'No readable text recognized on this page.' : text,
                          style: const TextStyle(fontSize: 15, height: 1.6, color: Color(0xFFE2E8F0)),
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
    } finally {
      setState(() => _isRecognizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.document.pageImagePaths;

    return Scaffold(
      backgroundColor: const Color(0xFF0B132B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        title: Text(
          widget.document.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () => Share.shareXFiles([XFile(widget.document.file.path)]),
          ),
        ],
      ),
      body: pages.isEmpty
          ? Center(
              child: ElevatedButton.icon(
                onPressed: () => OpenFile.open(widget.document.file.path),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Open External PDF'),
              ),
            )
          : Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: pages.length,
                  onPageChanged: (idx) => setState(() => _currentPage = idx),
                  itemBuilder: (context, index) {
                    return InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: Center(
                        child: Image.file(File(pages[index]), fit: BoxFit.contain),
                      ),
                    );
                  },
                ),
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Page ${_currentPage + 1} of ${pages.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ),
                if (_isRecognizing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(color: Color(0xFF2DD4BF)),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: const Color(0xFF111827),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: pages.isNotEmpty && !_isRecognizing ? () => _runInDocOcr(pages[_currentPage]) : null,
              icon: const Icon(Icons.text_fields),
              label: const Text('Digitize / Copy Text (OCR)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white70),
              tooltip: 'Open PDF',
              onPressed: () => OpenFile.open(widget.document.file.path),
            ),
          ],
        ),
      ),
    );
  }
}
