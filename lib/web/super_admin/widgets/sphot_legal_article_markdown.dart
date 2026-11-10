import 'package:flutter/material.dart';

/// Affiche les marqueurs Markdown des documents juridiques sans modifier
/// les textes conserves dans Firestore ou les brouillons de travail.
/// Le corpus actuel utilise principalement le gras et des listes.
class SphotLegalArticleMarkdown extends StatelessWidget {
  const SphotLegalArticleMarkdown({
    super.key,
    required this.markdown,
    this.selectable = false,
  });

  final String markdown;
  final bool selectable;

  static final RegExp _inline = RegExp(
    r'\*\*([^*\n]+)\*\*|\*([^*\n]+)\*|`([^`\n]+)`',
  );
  static final RegExp _heading = RegExp(r'^\s{0,3}#{1,6}\s+');
  static final RegExp _bullet = RegExp(r'^\s*[-+*]\s+');

  static List<InlineSpan> _inlineSpans(String text) {
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _inline.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      if (match.group(1) != null) {
        spans.add(TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(
          text: match.group(2),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else {
        spans.add(TextSpan(
          text: match.group(3),
          style: const TextStyle(fontFamily: 'monospace'),
        ));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    if (spans.isEmpty) spans.add(const TextSpan(text: ''));
    return spans;
  }

  static List<InlineSpan> _articleSpans(String value) {
    final lines = value.replaceAll('\r\n', '\n').split('\n');
    final result = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      final heading = _heading.firstMatch(line);
      if (heading != null) {
        line = line.substring(heading.end);
      } else {
        final bullet = _bullet.firstMatch(line);
        if (bullet != null) line = '•  ${line.substring(bullet.end)}';
      }
      result.add(TextSpan(
        children: _inlineSpans(line),
        style: heading == null
            ? null
            : const TextStyle(fontWeight: FontWeight.w700),
      ));
      if (i != lines.length - 1) result.add(const TextSpan(text: '\n'));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final content = TextSpan(children: _articleSpans(markdown));
    if (selectable) {
      return SelectableText.rich(content);
    }
    return Text.rich(
      content,
      style: const TextStyle(fontSize: 12, height: 1.45),
    );
  }
}
