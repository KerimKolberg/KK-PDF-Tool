class ScanDocument {
  final String id;
  String title;
  final DateTime createdAt;
  final int pageCount;

  ScanDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.pageCount,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'pageCount': pageCount,
      };

  factory ScanDocument.fromJson(Map<String, dynamic> json) => ScanDocument(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        pageCount: json['pageCount'] as int,
      );

  ScanDocument copyWith({String? title, int? pageCount}) => ScanDocument(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        pageCount: pageCount ?? this.pageCount,
      );
}
