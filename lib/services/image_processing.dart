import 'dart:typed_data';

import 'package:image/image.dart' as img;

enum ScanFilter { original, enhanced, grayscale, blackAndWhite }

extension ScanFilterLabel on ScanFilter {
  String get label {
    switch (this) {
      case ScanFilter.original:
        return 'Original';
      case ScanFilter.enhanced:
        return 'Farbe+';
      case ScanFilter.grayscale:
        return 'Graustufen';
      case ScanFilter.blackAndWhite:
        return 'Schwarz/Weiß';
    }
  }
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

  static img.Image applyFilter(img.Image src, ScanFilter filter) {
    switch (filter) {
      case ScanFilter.original:
        return src;
      case ScanFilter.enhanced:
        return img.adjustColor(src, contrast: 1.12, saturation: 1.15);
      case ScanFilter.grayscale:
        return img.grayscale(src);
      case ScanFilter.blackAndWhite:
        final gray = img.grayscale(src);
        return img.adjustColor(gray, contrast: 1.9, brightness: 1.02);
    }
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

/// Applies the perspective crop and filter chosen on [CropScreen].
///
/// Expects a map with:
///  - 'bytes': Uint8List, the working JPEG (already orientation-corrected)
///  - 'corners': `List<double>` of 8 values, x0,y0,x1,y1,x2,y2,x3,y3, ordered
///    topLeft, topRight, bottomRight, bottomLeft, in image pixel space
///  - 'filter': int index into [ScanFilter.values]
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
  image = ImageProcessing.applyFilter(image, ScanFilter.values[filterIndex]);
  return ImageProcessing.encodeJpg(image, quality: 92);
}
