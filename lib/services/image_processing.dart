import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Enum order is persisted (remembered filter), so new values go at the end;
/// [scanFilterOrder] controls how they're shown.
enum ScanFilter { original, enhanced, grayscale, blackAndWhite, document }

/// Order of the filter chips on the crop screen.
const scanFilterOrder = [
  ScanFilter.original,
  ScanFilter.document,
  ScanFilter.enhanced,
  ScanFilter.grayscale,
  ScanFilter.blackAndWhite,
];

extension ScanFilterLabel on ScanFilter {
  String get label {
    switch (this) {
      case ScanFilter.original:
        return 'Original';
      case ScanFilter.document:
        return 'Dokument';
      case ScanFilter.enhanced:
        return 'Farbe+';
      case ScanFilter.grayscale:
        return 'Graustufen';
      case ScanFilter.blackAndWhite:
        return 'Schwarz/Weiß';
    }
  }

  /// Filters that always even out lighting/shadows as part of their look.
  bool get includesShadowRemoval =>
      this == ScanFilter.document || this == ScanFilter.blackAndWhite;
}

class ImageProcessing {
  /// Warps the quadrilateral described by [corners] (in image pixel space,
  /// ordered topLeft, topRight, bottomRight, bottomLeft) into an upright
  /// rectangle, similar to how document scanner apps flatten a perspective
  /// photo of a page.
  static img.Image perspectiveCrop(img.Image src, List<img.Point> corners) {
    assert(corners.length == 4);
    return img.copyRectify(
      src,
      topLeft: corners[0],
      topRight: corners[1],
      bottomRight: corners[2],
      bottomLeft: corners[3],
      interpolation: img.Interpolation.cubic,
    );
  }

  static img.Image applyFilter(
    img.Image src,
    ScanFilter filter, {
    bool removeShadows = false,
  }) {
    switch (filter) {
      case ScanFilter.document:
        final image = normalizeBackground(_rgb(src));
        _documentLook(image);
        return sharpen(image);
      case ScanFilter.blackAndWhite:
        return _blackAndWhite(normalizeBackground(_rgb(src)));
      case ScanFilter.original:
      case ScanFilter.enhanced:
      case ScanFilter.grayscale:
        final image = removeShadows ? normalizeBackground(_rgb(src)) : src;
        return switch (filter) {
          ScanFilter.enhanced => img.adjustColor(image, contrast: 1.12, saturation: 1.15),
          ScanFilter.grayscale => img.grayscale(image),
          _ => image,
        };
    }
  }

  /// Plain 8-bit RGB whose byte buffer holds exactly its pixels, so the
  /// filters below can work on the raw buffer directly.
  static img.Image _rgb(img.Image src) {
    final isRgb8 = src.format == img.Format.uint8 && src.numChannels == 3 && !src.hasPalette;
    if (!isRgb8) return src.convert(format: img.Format.uint8, numChannels: 3);
    if (src.toUint8List().length == src.width * src.height * 3) return src;
    return img.Image.from(src);
  }

  /// Removes shadows and uneven lighting: estimates the paper colour across
  /// the page from a low-resolution map (text is thin and dark, so the
  /// brightest nearby cells show the paper), then divides it out so the
  /// paper becomes evenly white while ink keeps its colour. Works in place
  /// on an 8-bit RGB image.
  static img.Image normalizeBackground(img.Image image) {
    final w = image.width;
    final h = image.height;
    final data = image.toUint8List();

    const cells = 96;
    final scale = math.max(w, h) / cells;
    final sw = math.max(2, (w / scale).round());
    final sh = math.max(2, (h / scale).round());
    final small = img.copyResize(
      image,
      width: sw,
      height: sh,
      interpolation: img.Interpolation.average,
    );
    var bg = Float32List.fromList([
      for (final v in small.toUint8List()) v.toDouble(),
    ]);
    // Max filter removes thin dark text from the map; a smaller min filter
    // after it undoes most of the overshoot the max causes on gradients
    // (which would leave shadowed areas slightly grey) while keeping larger
    // coloured areas such as stamps from being washed out.
    bg = _rankFilter(bg, sw, sh, 2, max: true);
    bg = _rankFilter(bg, sw, sh, 1, max: false);
    bg = _boxBlur(bg, sw, sh, 2);
    bg = _boxBlur(bg, sw, sh, 2);

    // Horizontal interpolation positions are the same for every row.
    final x0 = Int32List(w);
    final x1 = Int32List(w);
    final tx = Float32List(w);
    for (var x = 0; x < w; x++) {
      final fx = ((x + 0.5) / w * sw - 0.5).clamp(0.0, sw - 1.0);
      x0[x] = fx.floor();
      x1[x] = math.min(x0[x] + 1, sw - 1);
      tx[x] = fx - x0[x];
    }

    const maxGain = 4.0;
    final rowBg = Float32List(sw * 3);
    for (var y = 0; y < h; y++) {
      final fy = ((y + 0.5) / h * sh - 0.5).clamp(0.0, sh - 1.0);
      final y0 = fy.floor();
      final y1 = math.min(y0 + 1, sh - 1);
      final ty = fy - y0;
      for (var i = 0; i < sw * 3; i++) {
        rowBg[i] = bg[y0 * sw * 3 + i] * (1 - ty) + bg[y1 * sw * 3 + i] * ty;
      }
      var p = y * w * 3;
      for (var x = 0; x < w; x++) {
        final a = x0[x] * 3;
        final b = x1[x] * 3;
        final t = tx[x];
        for (var c = 0; c < 3; c++) {
          final paper = rowBg[a + c] * (1 - t) + rowBg[b + c] * t;
          final gain = paper < 1 ? maxGain : math.min(255 / paper, maxGain);
          final v = data[p] * gain;
          data[p] = v > 255 ? 255 : v.toInt();
          p++;
        }
      }
    }
    return image;
  }

  /// Whitens near-white paper, deepens text and makes colours (stamps,
  /// highlighter) a bit more vivid. In place.
  static void _documentLook(img.Image image) {
    final data = image.toUint8List();
    final lut = Uint8List(256);
    const lo = 25.0;
    const hi = 228.0;
    for (var v = 0; v < 256; v++) {
      final t = ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
      lut[v] = (255 * math.pow(t, 1.15)).round();
    }
    for (var p = 0; p + 2 < data.length; p += 3) {
      final r = lut[data[p]];
      final g = lut[data[p + 1]];
      final b = lut[data[p + 2]];
      final l = 0.299 * r + 0.587 * g + 0.114 * b;
      data[p] = (l + (r - l) * 1.25).round().clamp(0, 255);
      data[p + 1] = (l + (g - l) * 1.25).round().clamp(0, 255);
      data[p + 2] = (l + (b - l) * 1.25).round().clamp(0, 255);
    }
  }

  static img.Image _blackAndWhite(img.Image image) {
    final data = image.toUint8List();
    final lut = Uint8List(256);
    const lo = 95.0;
    const hi = 205.0;
    for (var v = 0; v < 256; v++) {
      lut[v] = (((v - lo) / (hi - lo)).clamp(0.0, 1.0) * 255).round();
    }
    for (var p = 0; p + 2 < data.length; p += 3) {
      final l = (0.299 * data[p] + 0.587 * data[p + 1] + 0.114 * data[p + 2]).round();
      final v = lut[l];
      data[p] = v;
      data[p + 1] = v;
      data[p + 2] = v;
    }
    return image;
  }

  /// Mild unsharp mask (4-neighbour Laplacian) for crisper text.
  static img.Image sharpen(img.Image image, {double amount = 0.55}) {
    final w = image.width;
    final h = image.height;
    final src = image.toUint8List();
    final out = Uint8List.fromList(src);
    final stride = w * 3;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final p = y * stride + x * 3;
        for (var c = 0; c < 3; c++) {
          final i = p + c;
          final center = src[i];
          final lap = 4 * center - src[i - 3] - src[i + 3] - src[i - stride] - src[i + stride];
          final v = center + amount * lap;
          out[i] = v < 0 ? 0 : (v > 255 ? 255 : v.round());
        }
      }
    }
    return img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 3);
  }

  /// Separable max (dilation) or min (erosion) filter over 3-channel data.
  static Float32List _rankFilter(Float32List src, int w, int h, int r, {required bool max}) {
    final tmp = Float32List(src.length);
    final out = Float32List(src.length);
    double pick(double a, double b) => max ? math.max(a, b) : math.min(a, b);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        for (var c = 0; c < 3; c++) {
          var m = src[(y * w + x) * 3 + c];
          for (var dx = -r; dx <= r; dx++) {
            m = pick(m, src[(y * w + (x + dx).clamp(0, w - 1)) * 3 + c]);
          }
          tmp[(y * w + x) * 3 + c] = m;
        }
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        for (var c = 0; c < 3; c++) {
          var m = tmp[(y * w + x) * 3 + c];
          for (var dy = -r; dy <= r; dy++) {
            m = pick(m, tmp[((y + dy).clamp(0, h - 1) * w + x) * 3 + c]);
          }
          out[(y * w + x) * 3 + c] = m;
        }
      }
    }
    return out;
  }

  static Float32List _boxBlur(Float32List src, int w, int h, int r) {
    final tmp = Float32List(src.length);
    final out = Float32List(src.length);
    final n = 2 * r + 1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        for (var c = 0; c < 3; c++) {
          var sum = 0.0;
          for (var dx = -r; dx <= r; dx++) {
            sum += src[(y * w + (x + dx).clamp(0, w - 1)) * 3 + c];
          }
          tmp[(y * w + x) * 3 + c] = sum / n;
        }
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        for (var c = 0; c < 3; c++) {
          var sum = 0.0;
          for (var dy = -r; dy <= r; dy++) {
            sum += tmp[((y + dy).clamp(0, h - 1) * w + x) * 3 + c];
          }
          out[(y * w + x) * 3 + c] = sum / n;
        }
      }
    }
    return out;
  }

  static Uint8List encodeJpg(img.Image image, {int quality = 90}) {
    return img.encodeJpg(image, quality: quality);
  }
}

/// Top-level functions below are entry points for [compute], so each one
/// must be a plain function (no closures) and only exchange primitive /
/// typed-data values with the calling isolate.

/// Normalises EXIF rotation into actual pixel data and re-encodes as JPEG.
Uint8List bakeOrientationJpegIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Bild konnte nicht gelesen werden');
  }
  final baked = img.bakeOrientation(decoded);
  return img.encodeJpg(baked, quality: 95);
}

/// Rotates a JPEG by 90 degrees clockwise and re-encodes it.
Uint8List rotateJpeg90Isolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Bild konnte nicht gelesen werden');
  }
  final rotated = img.copyRotate(decoded, angle: 90);
  return img.encodeJpg(rotated, quality: 95);
}

/// Shrinks an image so its longer side is at most 'maxSide' (for fast
/// filter previews). Expects {'bytes': Uint8List, 'maxSide': int}.
Uint8List downscaleJpegIsolate(Map<String, dynamic> args) {
  final decoded = img.decodeImage(args['bytes'] as Uint8List);
  if (decoded == null) {
    throw const FormatException('Bild konnte nicht gelesen werden');
  }
  final maxSide = args['maxSide'] as int;
  final longer = math.max(decoded.width, decoded.height);
  final small = longer <= maxSide
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxSide : null,
          height: decoded.width < decoded.height ? maxSide : null,
          interpolation: img.Interpolation.average,
        );
  return img.encodeJpg(small, quality: 85);
}

/// Applies a filter to a (small) preview image.
/// Expects {'bytes': Uint8List, 'filter': int, 'shadows': bool}.
Uint8List previewFilterIsolate(Map<String, dynamic> args) {
  final decoded = img.decodeImage(args['bytes'] as Uint8List);
  if (decoded == null) {
    throw const FormatException('Bild konnte nicht gelesen werden');
  }
  final filtered = ImageProcessing.applyFilter(
    decoded,
    ScanFilter.values[args['filter'] as int],
    removeShadows: args['shadows'] as bool? ?? false,
  );
  return img.encodeJpg(filtered, quality: 85);
}

/// Applies the perspective crop and filter chosen on [CropScreen].
///
/// Expects a map with:
///  - 'bytes': Uint8List, the working JPEG (already orientation-corrected)
///  - 'corners': `List<double>` of 8 values, x0,y0,x1,y1,x2,y2,x3,y3, ordered
///    topLeft, topRight, bottomRight, bottomLeft, in image pixel space
///  - 'filter': int index into [ScanFilter.values]
///  - 'shadows': bool, remove shadows (for filters that don't already)
Uint8List processPageIsolate(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final cornersFlat = (args['corners'] as List).cast<num>();
  final filterIndex = args['filter'] as int;

  var image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException('Bild konnte nicht gelesen werden');
  }

  final corners = <img.Point>[
    for (var i = 0; i < 8; i += 2)
      img.Point(cornersFlat[i].toDouble(), cornersFlat[i + 1].toDouble()),
  ];

  image = ImageProcessing.perspectiveCrop(image, corners);
  image = ImageProcessing.applyFilter(
    image,
    ScanFilter.values[filterIndex],
    removeShadows: args['shadows'] as bool? ?? false,
  );
  return ImageProcessing.encodeJpg(image, quality: 92);
}
