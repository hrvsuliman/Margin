// Recognising videos and fetching titles for pinned links
// (PinLinks in Margin/Features/Subjects/SubjectBoard.swift).

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

abstract final class PinLinks {
  static String? youTubeId(Uri url) {
    final host = url.host.toLowerCase();
    final parts = url.pathSegments.where((p) => p.isNotEmpty).toList();
    if (host.endsWith('youtu.be')) return parts.isEmpty ? null : parts.first;
    if (!host.endsWith('youtube.com')) return null;
    final v = url.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    final index = parts.indexWhere((p) => p == 'shorts' || p == 'embed' || p == 'live');
    return index >= 0 && index + 1 < parts.length ? parts[index + 1] : null;
  }

  static bool isVideoHost(Uri url) {
    final host = url.host.toLowerCase();
    return ['vimeo.com', 'tiktok.com', 'simpleclub', 'sofatutor', 'dailymotion.com'].any(host.contains);
  }

  static String thumbnail(String id) => 'https://img.youtube.com/vi/$id/hqdefault.jpg';

  /// "youtube.com/watch?v=…" → "https://youtube.com/watch?v=…"; null if it isn't a web address.
  static Uri? parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasAuthority || !uri.host.contains('.')) return null;
    return uri;
  }

  /// The page title (YouTube via oEmbed, otherwise the HTML <title>). Null when offline.
  static Future<String?> title(Uri url) async {
    try {
      if (youTubeId(url) != null) {
        final endpoint = Uri.https('www.youtube.com', '/oembed', {'url': url.toString(), 'format': 'json'});
        final response = await http.get(endpoint).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final title = (jsonDecode(response.body) as Map)['title'];
          if (title is String && title.isNotEmpty) return title;
        }
      }
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      final body = response.bodyBytes.length > 200000 ? response.bodyBytes.sublist(0, 200000) : response.bodyBytes;
      return htmlTitle(utf8.decode(body, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  static String? htmlTitle(String html) {
    final match = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html);
    if (match == null) return null;
    final title = match
        .group(1)!
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
    if (title.isEmpty) return null;
    return title.length > 120 ? title.substring(0, 120) : title;
  }
}

/// A photo for the pinboard: upright, at most 1600 px, JPEG – small enough to sync.
Future<String> compressPhoto(Uint8List bytes) => Isolate.run(() {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw const FormatException('Das Bild konnte nicht gelesen werden.');
      var image = img.bakeOrientation(decoded);
      if (image.width > 1600 || image.height > 1600) {
        image = image.width >= image.height
            ? img.copyResize(image, width: 1600, interpolation: img.Interpolation.average)
            : img.copyResize(image, height: 1600, interpolation: img.Interpolation.average);
      }
      return base64Encode(img.encodeJpg(image, quality: 80));
    });
