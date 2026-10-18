import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MaterialApp(
    home: ScannerHomePage(),
    debugShowCheckedModeBanner: false,
  ));
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

class _ScannerHomePageState extends State<ScannerHomePage> {
  List<File> _scannedPdfs = [];

  @override
  void initState() {
    super.initState();
    _loadSavedFiles();
  }

  Future<void> _loadSavedFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.pdf')).toList();
    setState(() {
      _scannedPdfs = files.reversed.toList();
    });
  }

  Future<void> _startScan() async {
    try {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormats: {DocumentFormat.pdf, DocumentFormat.jpeg},
          mode: ScannerMode.full,
          isGalleryImport: true,
          pageLimit: 25,
        ),
      );

      final result = await scanner.scanDocument();
      final pdfUri = result.pdf?.uri;

      if (pdfUri != null && pdfUri.isNotEmpty) {
        final rawPath = Uri.parse(pdfUri).path;
        final dir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final newFile = File('${dir.path}/Scan_$timestamp.pdf');
        
        await File(rawPath).copy(newFile.path);
        _loadSavedFiles();
      }
      
      await scanner.close();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scanner error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Private Scanner'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _scannedPdfs.isEmpty
          ? const Center(
              child: Text(
                'No scans yet.\nTap the camera button to scan a document!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: _scannedPdfs.length,
              itemBuilder: (context, index) {
                final file = _scannedPdfs[index];
                final name = file.path.split('/').last;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 36),
                    title: Text(name),
                    subtitle: const Text('Tap to view or share'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => OpenFile.open(file.path),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startScan,
        label: const Text('Scan Document'),
        icon: const Icon(Icons.camera_alt),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
    );
  }
}
