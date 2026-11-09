import 'package:flutter_test/flutter_test.dart';
import 'package:bathing_spots_app/web/admin/services/admin_cgv_live_service.dart';

void main() {
  Map<String, dynamic> published({
    String version = '1.1',
    int revision = 2,
    List<Map<String, dynamic>>? chapters,
  }) => {
    'published': true,
    'testOnly': false,
    'version': version,
    'revision': revision,
    'chapters': chapters ?? [
      {'title': 'Article 1', 'content': 'Conditions complètes', 'order': 1},
    ],
  };

  test('charge uniquement la version officielle complète', () {
    final document = AdminCgvLiveDocument.fromData(published());
    expect(document.versionId, '1.1:r2');
    expect(document.chapters.single.title, 'Article 1');
  });

  test('refuse le corpus de test et les brouillons non publiés', () {
    expect(
      () => AdminCgvLiveDocument.fromData({
        ...published(), 'testOnly': true,
      }),
      throwsStateError,
    );
    expect(
      () => AdminCgvLiveDocument.fromData({
        ...published(), 'published': false,
      }),
      throwsStateError,
    );
  });

  test('refuse toute version ou tout article incomplet', () {
    expect(
      () => AdminCgvLiveDocument.fromData(published(version: '')),
      throwsStateError,
    );
    expect(
      () => AdminCgvLiveDocument.fromData(published(revision: -1)),
      throwsStateError,
    );
    expect(
      () => AdminCgvLiveDocument.fromData(published(chapters: [
        {'title': 'Article sans contenu', 'content': ''},
      ])),
      throwsStateError,
    );
  });

  test('lit les articles historiques en sous-collection sans les inventer', () {
    final data = published()..remove('chapters');
    final document = AdminCgvLiveDocument.fromData(
      data,
      fallbackChapters: [
        {'title': 'Article 2', 'content': 'B', 'order': 2},
        {'title': 'Article 1', 'content': 'A', 'order': 1},
      ],
    );
    expect(document.chapters.map((a) => a.title).toList(),
      ['Article 1', 'Article 2']);
    expect(
      () => AdminCgvLiveDocument.fromData(data),
      throwsStateError,
    );
  });

  test('une nouvelle publication change la clé de présentation', () {
    final original = AdminCgvLiveDocument.fromData(published());
    final revised = AdminCgvLiveDocument.fromData(published(revision: 3));
    expect(revised.presentationSignature,
      isNot(original.presentationSignature));
  });
}
