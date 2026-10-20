import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

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

enum ScanColorFilter { original, magicColor, grayscale, highContrastBW }

extension ScanColorFilterLabel on ScanColorFilter {
  String get label {
    switch (this) {
      case ScanColorFilter.original:
        return 'Original';
      case ScanColorFilter.magicColor:
        return 'Magic Color';
      case ScanColorFilter.grayscale:
        return 'Grayscale';
      case ScanColorFilter.highContrastBW:
        return 'B&W Crisp';
    }
  }
}

enum ConversionDirection {
  pdfToImage,
  imageToPdf,
  pdfToWord,
  wordToPdf,
  pdfToExcel,
  excelToPdf,
  wordToExcel,
  excelToWord,
}

class OcrWordBox {
  final String text;
  final Rect boundingBox;
  OcrWordBox({required this.text, required this.boundingBox});
}

class GlobalSearchMatch {
  final int pageIndex;
  final String matchedLine;
  final Rect wordRect;

  GlobalSearchMatch({
    required this.pageIndex,
    required this.matchedLine,
    required this.wordRect,
  });
}

class BlemishEraserStroke {
  final List<Offset> normalizedPoints;
  final Color sampledColor;
  final double strokeWidth;

  BlemishEraserStroke({
    required this.normalizedPoints,
    required this.sampledColor,
    required this.strokeWidth,
  });
}

class OverlayImageItem {
  Uint8List bytes;
  Offset normalizedPos;
  double normalizedWidth;
  double normalizedHeight;

  OverlayImageItem({
    required this.bytes,
    this.normalizedPos = const Offset(0.3, 0.3),
    this.normalizedWidth = 0.40,
    this.normalizedHeight = 0.25,
  });
}

class PageAnnotationItem {
  final String type;
  String text;
  Offset normalizedPos;
  Color color;
  double fontSize;
  final Uint8List? signaturePng;

  PageAnnotationItem({
    required this.type,
    this.text = '',
    this.normalizedPos = const Offset(0.5, 0.5),
    this.color = const Color(0xFF0F172A),
    this.fontSize = 18.0,
    this.signaturePng,
  });
}

class EditableDocumentPage {
  Uint8List originalBytes;
  Uint8List displayBytes;
  int imageWidth;
  int imageHeight;
  int rotationQuarterTurns;
  ScanColorFilter activeFilter;
  List<OcrWordBox> ocrWords;
  List<PageAnnotationItem> annotations;
  List<BlemishEraserStroke> eraserStrokes;
  List<OverlayImageItem> overlayImages;

  EditableDocumentPage({
    required this.originalBytes,
    required this.displayBytes,
    this.imageWidth = 1000,
    this.imageHeight = 1400,
    this.rotationQuarterTurns = 0,
    this.activeFilter = ScanColorFilter.original,
    List<OcrWordBox>? ocrWords,
    List<PageAnnotationItem>? annotations,
    List<BlemishEraserStroke>? eraserStrokes,
    List<OverlayImageItem>? overlayImages,
  })  : ocrWords = ocrWords ?? [],
        annotations = annotations ?? [],
        eraserStrokes = eraserStrokes ?? [],
        overlayImages = overlayImages ?? [];
}

enum OcrLanguageMode { english, hindiDevanagari, punjabiGurmukhi }

extension OcrLanguageLabel on OcrLanguageMode {
  String get label {
    switch (this) {
      case OcrLanguageMode.english:
        return 'English';
      case OcrLanguageMode.hindiDevanagari:
        return 'Hindi (हिंदी)';
      case OcrLanguageMode.punjabiGurmukhi:
        return 'Punjabi (ਪੰਜਾਬੀ)';
    }
  }
}
