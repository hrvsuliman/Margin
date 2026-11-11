// A vector PDF with one A4 page per laid-out page, like PageRenderer.pdf on the iPhone.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';

import 'note_layout.dart';

abstract final class NotePdf {
  static Future<Uint8List> build(List<LaidOutPage> pages, PageSettings settings,
      {required String title, bool compress = true}) {
    final document = PdfDocument(compress: compress);
    document.info = PdfInfo(document, title: title, creator: 'Margin');
    final fallbackFont = PdfFont.helveticaOblique(document);
    final height = settings.pageHeight;
    final ink = PdfColor.fromInt(0xFF000000 | settings.penColor.hex);
    // 75 % ink on paper, like the iPhone's fallback text.
    final faintInk = PdfColor(
      ink.red * 0.75 + 0.25,
      ink.green * 0.75 + 0.25,
      ink.blue * 0.75 + 0.25,
    );

    for (final page in pages) {
      final pdfPage = PdfPage(document, pageFormat: PdfPageFormat(settings.pageWidth, settings.pageHeight));
      final g = pdfPage.getGraphics();

      g.setFillColor(PdfColor.fromInt(0xFFFFFEFB));
      g.drawRect(0, 0, settings.pageWidth, settings.pageHeight);
      g.fillPath();
      if (settings.printPaper) _drawPaper(g, settings);

      // PDF's y axis points up; the layout's points down.
      if (page.ink.isNotEmpty) {
        g.setFillColor(ink);
        for (final polygon in page.ink) {
          g.moveTo(polygon[0].x, height - polygon[0].y);
          for (var i = 1; i < polygon.length; i++) {
            g.lineTo(polygon[i].x, height - polygon[i].y);
          }
          g.closePath();
        }
        g.fillPath();
      }

      if (page.fallbacks.isNotEmpty) {
        g.setFillColor(faintInk);
        for (final fallback in page.fallbacks) {
          g.drawString(fallbackFont, fallback.fontSize, _latin1(fallback.text), fallback.origin.x, height - fallback.origin.y);
        }
      }
    }
    return document.save();
  }

  /// The built-in PDF fonts only know Latin-1 characters.
  static String _latin1(String text) =>
      String.fromCharCodes(text.runes.map((r) => r <= 0xFF ? r : 0x3F /* ? */));

  static void _drawPaper(PdfGraphics g, PageSettings s) {
    final width = s.pageWidth;
    final height = s.pageHeight;
    final step = PageSettings.mm(5);
    switch (s.paper) {
      case PaperStyle.lined:
        g.setStrokeColor(PdfColor.fromInt(0xFF9FBAD6));
        g.setLineWidth(0.6);
        for (var y = s.marginTop + s.lineSpacing; y < height - PageSettings.mm(8); y += s.lineSpacing) {
          g.moveTo(0, height - y);
          g.lineTo(width, height - y);
        }
        g.strokePath();
      case PaperStyle.squared:
        g.setStrokeColor(PdfColor.fromInt(0xFFC3CDD8));
        g.setLineWidth(0.4);
        for (var y = s.marginTop % step; y < height; y += step) {
          g.moveTo(0, height - y);
          g.lineTo(width, height - y);
        }
        for (var x = s.marginLeft % step; x < width; x += step) {
          g.moveTo(x, 0);
          g.lineTo(x, height);
        }
        g.strokePath();
      case PaperStyle.dotted:
        g.setFillColor(PdfColor.fromInt(0xFFC3CDD8));
        for (var y = s.marginTop % step; y < height; y += step) {
          for (var x = s.marginLeft % step; x < width; x += step) {
            g.drawEllipse(x, height - y, 0.7, 0.7);
          }
        }
        g.fillPath();
      case PaperStyle.blank:
        break;
    }
    if (s.showMarginLine && s.paper != PaperStyle.blank) {
      final x = width - s.marginRight + PageSettings.mm(4);
      g.setStrokeColor(PdfColor.fromInt(0xFFE08A7E));
      g.setLineWidth(0.7);
      g.moveTo(x, 0);
      g.lineTo(x, height);
      g.strokePath();
    }
  }
}
