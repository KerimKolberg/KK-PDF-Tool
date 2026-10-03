/// One recognised line of text, positioned in the pixel space of the image
/// the OCR engine saw ([OcrResult.width] x [OcrResult.height]).
class OcrLine {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
}

class OcrResult {
  final String text;
  final int width;
  final int height;
  final List<OcrLine> lines;

  const OcrResult({
    required this.text,
    required this.width,
    required this.height,
    required this.lines,
  });

  Map<String, dynamic> toMap() => {
        'text': text,
        'width': width,
        'height': height,
        'lines': [
          for (final l in lines)
            {'text': l.text, 'left': l.left, 'top': l.top, 'right': l.right, 'bottom': l.bottom},
        ],
      };

  factory OcrResult.fromMap(Map<dynamic, dynamic> map) {
    double n(dynamic v) => (v as num).toDouble();
    return OcrResult(
      text: (map['text'] as String?) ?? '',
      width: (map['width'] as num).toInt(),
      height: (map['height'] as num).toInt(),
      lines: [
        for (final raw in (map['lines'] as List? ?? const []))
          OcrLine(
            text: (raw as Map)['text'] as String,
            left: n(raw['left']),
            top: n(raw['top']),
            right: n(raw['right']),
            bottom: n(raw['bottom']),
          ),
      ],
    );
  }
}
