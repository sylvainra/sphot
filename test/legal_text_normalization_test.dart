import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bathing_spots_app/services/sphot_legal_text_normalization.dart';

void main() {
  test('LF, CRLF et CR sont identiques sans modifier les mots', () {
    const approved = 'Premier paragraphe.\n\nDeuxième paragraphe.';
    expect(normalizeSphotLegalText(
      'Premier paragraphe.\r\n\r\nDeuxième paragraphe.\r\n',
    ), approved);
    expect(normalizeSphotLegalText(
      'Premier paragraphe.\r\rDeuxième paragraphe.\r',
    ), approved);
    expect(normalizeSphotLegalText('Premier paragraphe modifié.\r\n'),
        isNot(normalizeSphotLegalText('Premier paragraphe.\n')));
  });

  final corpus = <(String, String, int)>[
    ('adminCgu', 'cgu_admin.md', 14),
    ('advertiserCgu', 'cgu_publicitaire.md', 12),
    ('sauveteurCgu', 'cgu_sauveteur.md', 8),
    ('sauveteurCharter', 'charte_sauveteur.md', 7),
  ];

  for (final (id, filename, count) in corpus) {
    test('$id : titres et textes Markdown correspondent au JSON Firebase',
        () {
      final rawMarkdown = File(
        'assets/legal/prepublication_2026_11_11/$filename',
      ).readAsStringSync();
      final markdown = normalizeSphotLegalText(rawMarkdown);
      final json = jsonDecode(File(
        'functions-legal/legal_sources/$id.json',
      ).readAsStringSync()) as Map<String, dynamic>;
      final chapters = (json['chapters'] as List).cast<Map<String, dynamic>>();
      final headings = RegExp(r'^##\s+(.+)$', multiLine: true)
          .allMatches(markdown).toList();

      expect(headings.length, count);
      expect(chapters.length, count);
      for (var i = 0; i < count; i++) {
        final heading = headings[i];
        final end = i + 1 < headings.length
            ? headings[i + 1].start : markdown.length;
        final text = normalizeSphotLegalText(
          markdown.substring(heading.end, end),
        );
        expect(chapters[i]['id'], (i + 1).toString().padLeft(2, '0'));
        expect(chapters[i]['title'], heading.group(1)!.trim());
        expect(normalizeSphotLegalText(chapters[i]['content'] as String), text);
      }
    });
  }
}
