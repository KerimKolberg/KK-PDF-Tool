class ScanDocument {
  final String id;
  String title;
  final DateTime createdAt;
  final int pageCount;

  /// Name of the library folder this document lives in; null = no folder.
  final String? folder;

  ScanDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.pageCount,
    this.folder,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'pageCount': pageCount,
        if (folder != null) 'folder': folder,
      };

  factory ScanDocument.fromJson(Map<String, dynamic> json) => ScanDocument(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        pageCount: json['pageCount'] as int,
        folder: json['folder'] as String?,
      );

  static const _keep = Object();

  /// Pass `folder: null` to remove the document from its folder; omit it
  /// to keep the current one.
  ScanDocument copyWith({String? title, int? pageCount, Object? folder = _keep}) =>
      ScanDocument(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        pageCount: pageCount ?? this.pageCount,
        folder: identical(folder, _keep) ? this.folder : folder as String?,
      );
}
