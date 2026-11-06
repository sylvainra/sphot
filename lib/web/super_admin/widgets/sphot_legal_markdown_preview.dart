import 'package:flutter/material.dart';

/// Lecture seule du sous-ensemble Markdown utilisé par les brouillons SPHOT.
/// Le texte source reste intact dans le champ d'édition et dans Firestore.
class SphotLegalMarkdownPreview extends StatelessWidget {
  const SphotLegalMarkdownPreview({
    super.key,
    required this.source,
    this.bodyStyle = _defaultBodyStyle,
  });

  final String source;
  final TextStyle bodyStyle;

  static const TextStyle _defaultBodyStyle = TextStyle(
    fontSize: 14,
    height: 1.55,
    color: Color(0xFF253048),
  );

  static final RegExp _boldPattern = RegExp(r'\*\*(.+?)\*\*');
  static final RegExp _listPattern = RegExp(r'^([-*]|\d+\.)\s+(.+)$');

  static List<InlineSpan> _inlineSpans(String source) {
    final spans = <InlineSpan>[];
    var from = 0;
    for (final match in _boldPattern.allMatches(source)) {
      if (match.start > from) {
        spans.add(TextSpan(text: source.substring(from, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1) ?? '',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ));
      from = match.end;
    }
    if (from < source.length) {
      spans.add(TextSpan(text: source.substring(from)));
    }
    return spans;
  }

  Widget _paragraph(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SelectableText.rich(
          TextSpan(style: bodyStyle, children: _inlineSpans(text)),
        ),
      );

  Widget _listItem(String marker, String text) => Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                marker == '-' || marker == '*' ? '•' : marker,
                style: bodyStyle.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: SelectableText.rich(
                TextSpan(style: bodyStyle, children: _inlineSpans(text)),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    final paragraphLines = <String>[];

    void finishParagraph() {
      if (paragraphLines.isEmpty) return;
      blocks.add(_paragraph(paragraphLines.join(' ').trim()));
      paragraphLines.clear();
    }

    for (final rawLine in source.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        finishParagraph();
        continue;
      }

      if (line.startsWith('### ')) {
        finishParagraph();
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: SelectableText(
            line.substring(4),
            style: bodyStyle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E3A8A),
            ),
          ),
        ));
        continue;
      }

      final listMatch = _listPattern.firstMatch(line);
      if (listMatch != null) {
        finishParagraph();
        blocks.add(_listItem(
          listMatch.group(1) ?? '-',
          listMatch.group(2) ?? '',
        ));
        continue;
      }

      paragraphLines.add(line);
    }
    finishParagraph();

    if (blocks.isEmpty) {
      return const Text('Aucun contenu à afficher.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }
}
