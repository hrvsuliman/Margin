// Draws laid-out pages on screen: paper, handwriting and fallback text.
// The PDF (pdf_export.dart) draws the same things. Ported from PageRenderer.swift.

import 'package:flutter/material.dart';

import 'note_layout.dart';

abstract final class PageColors {
  static const paper = Color(0xFFFFFEFB);
  static const rule = Color(0xFF9FBAD6);
  static const grid = Color(0xFFC3CDD8);
  static const margin = Color(0xFFE08A7E);

  static Color pen(PenColor pen) => Color(0xFF000000 | pen.hex);
}

/// One page, scaled to the widget's width.
class NotePagePainter extends CustomPainter {
  NotePagePainter(this.page, this.settings, {this.includePaper = true});

  final LaidOutPage? page;
  final PageSettings settings;
  final bool includePaper;

  static final _paths = Expando<Path>();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / settings.pageWidth;
    canvas.save();
    canvas.scale(scale);
    canvas.drawRect(Rect.fromLTWH(0, 0, settings.pageWidth, settings.pageHeight), Paint()..color = PageColors.paper);
    if (includePaper) _drawPaper(canvas);

    final page = this.page;
    if (page != null) {
      final ink = PageColors.pen(settings.penColor);
      canvas.drawPath(_paths[page] ??= _inkPath(page), Paint()..color = ink);
      for (final fallback in page.fallbacks) {
        final painter = TextPainter(
          text: TextSpan(
            text: fallback.text,
            style: TextStyle(
              fontFamily: 'Arial',
              fontStyle: FontStyle.italic,
              fontSize: fallback.fontSize,
              color: ink.withValues(alpha: 0.75),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final ascent = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        painter.paint(canvas, Offset(fallback.origin.x, fallback.origin.y - ascent));
        painter.dispose();
      }
    }
    canvas.restore();
  }

  static Path _inkPath(LaidOutPage page) {
    final path = Path()..fillType = PathFillType.nonZero;
    for (final polygon in page.ink) {
      path.moveTo(polygon[0].x, polygon[0].y);
      for (var i = 1; i < polygon.length; i++) {
        path.lineTo(polygon[i].x, polygon[i].y);
      }
      path.close();
    }
    return path;
  }

  void _drawPaper(Canvas canvas) {
    final width = settings.pageWidth;
    final height = settings.pageHeight;
    final step = PageSettings.mm(5);
    switch (settings.paper) {
      case PaperStyle.lined:
        final paint = Paint()
          ..color = PageColors.rule
          ..strokeWidth = 0.6;
        for (var y = settings.marginTop + settings.lineSpacing; y < height - PageSettings.mm(8); y += settings.lineSpacing) {
          canvas.drawLine(Offset(0, y), Offset(width, y), paint);
        }
      case PaperStyle.squared:
        final paint = Paint()
          ..color = PageColors.grid
          ..strokeWidth = 0.4;
        for (var y = settings.marginTop % step; y < height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(width, y), paint);
        }
        for (var x = settings.marginLeft % step; x < width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, height), paint);
        }
      case PaperStyle.dotted:
        final paint = Paint()..color = PageColors.grid;
        for (var y = settings.marginTop % step; y < height; y += step) {
          for (var x = settings.marginLeft % step; x < width; x += step) {
            canvas.drawCircle(Offset(x, y), 0.7, paint);
          }
        }
      case PaperStyle.blank:
        break;
    }
    if (settings.showMarginLine && settings.paper != PaperStyle.blank) {
      // German correction margin on the right.
      final x = width - settings.marginRight + PageSettings.mm(4);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, height),
        Paint()
          ..color = PageColors.margin
          ..strokeWidth = 0.7,
      );
    }
  }

  @override
  bool shouldRepaint(NotePagePainter old) =>
      !identical(old.page, page) || !identical(old.settings, settings) || old.includePaper != includePaper;
}
