import 'package:cloud_firestore/cloud_firestore.dart';

/// Document contractuel ADMIN, chargé uniquement depuis la publication active.
/// Le corpus de test et les brouillons éditoriaux ne sont jamais consultés ici.
class AdminCgvLiveDocument {
  const AdminCgvLiveDocument({
    required this.version,
    required this.revision,
    required this.chapters,
    this.publishedAt,
  });

  final String version;
  final int revision;
  final DateTime? publishedAt;
  final List<AdminCgvLiveChapter> chapters;

  String get versionId => '$version:r$revision';

  /// Clé de présentation : une nouvelle publication, même corrigée à tort
  /// sans incrément de révision, efface le choix local de la case à cocher.
  int get presentationSignature => Object.hash(
        version,
        revision,
        publishedAt?.millisecondsSinceEpoch,
        Object.hashAll(chapters.map((chapter) => Object.hash(
              chapter.title,
              chapter.content,
              chapter.order,
            ))),
      );

  static AdminCgvLiveDocument fromData(
    Map<String, dynamic> data, {
    List<Map<String, dynamic>>? fallbackChapters,
  }) {
    if (data['published'] != true || data['testOnly'] == true) {
      throw StateError('Les CGV SPHOT Admin ne sont pas publiées.');
    }

    final version = (data['version'] ?? '').toString().trim();
    final revision = data['revision'];
    if (version.isEmpty || revision is! int || revision < 0) {
      throw StateError('La version publiée des CGV est incomplète.');
    }

    final inline = data['chapters'];
    final source = inline is List && inline.isNotEmpty
        ? inline
        : fallbackChapters;
    if (source == null || source.isEmpty) {
      throw StateError('Le texte publié des CGV est indisponible.');
    }

    final chapters = <AdminCgvLiveChapter>[];
    for (var index = 0; index < source.length; index++) {
      final raw = source[index];
      if (raw is! Map) {
        throw StateError('Un article des CGV publiées est illisible.');
      }
      final article = Map<String, dynamic>.from(raw);
      final title = (article['title'] ?? article['titre'] ?? '')
          .toString().trim();
      final content = (article['content'] ?? article['texte'] ?? '')
          .toString().trim();
      if (title.isEmpty || content.isEmpty || article['isActive'] == false) {
        throw StateError('Un article des CGV publiées est incomplet.');
      }
      final orderValue = article['order'];
      chapters.add(AdminCgvLiveChapter(
        title: title,
        content: content,
        order: orderValue is num ? orderValue.toInt() : index + 1,
      ));
    }
    chapters.sort((a, b) => a.order.compareTo(b.order));

    final rawDate = data['publishedAt'];
    DateTime? publishedAt;
    if (rawDate is Timestamp) publishedAt = rawDate.toDate();
    if (rawDate is DateTime) publishedAt = rawDate;

    return AdminCgvLiveDocument(
      version: version,
      revision: revision,
      chapters: List.unmodifiable(chapters),
      publishedAt: publishedAt,
    );
  }
}

class AdminCgvLiveChapter {
  const AdminCgvLiveChapter({
    required this.title,
    required this.content,
    required this.order,
  });

  final String title;
  final String content;
  final int order;
}

class AdminCgvLiveService {
  const AdminCgvLiveService._();

  static Stream<AdminCgvLiveDocument> watchPublished() {
    final reference = FirebaseFirestore.instance
        .collection('legalDocuments')
        .doc('adminCgv');

    return reference.snapshots().asyncMap((snapshot) async {
      final data = snapshot.data();
      if (data == null || data['published'] != true ||
          data['testOnly'] == true) {
        throw StateError('Aucune CGV SPHOT Admin officielle publiée.');
      }

      // Les nouvelles publications contiennent directement tous les articles
      // dans le document parent. Les versions historiques peuvent utiliser
      // uniquement la sous-collection « chapters ».
      final inline = data['chapters'];
      if (inline is List && inline.isNotEmpty) {
        return AdminCgvLiveDocument.fromData(data);
      }

      final rows = await reference.collection('chapters').get();
      final current = await reference.get();
      final latest = current.data();
      if (latest == null || latest['published'] != true ||
          latest['testOnly'] == true ||
          latest['version'] != data['version'] ||
          latest['revision'] != data['revision']) {
        throw StateError('Les CGV ont changé pendant leur chargement.');
      }

      return AdminCgvLiveDocument.fromData(
        latest,
        fallbackChapters: rows.docs.map((row) => {
          ...row.data(),
          'id': row.id,
        }).toList(),
      );
    });
  }
}
