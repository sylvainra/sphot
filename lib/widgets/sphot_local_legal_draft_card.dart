import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../web/super_admin/widgets/sphot_legal_markdown_preview.dart';

/// Consultation visuelle des brouillons juridiques, exclusivement dans
/// une session Flutter DEBUG ouverte sur localhost.
///
/// Ne lit pas Firebase C4, n'enregistre aucune acceptation et ne publie rien.
class SphotLocalLegalDraftCard extends StatefulWidget {
  const SphotLocalLegalDraftCard({
    super.key,
    required this.assetPath,
    required this.documentTitle,
    this.version = '1.0',
  });

  final String assetPath;
  final String documentTitle;
  final String version;

  static bool get available =>
      kDebugMode &&
      (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1');

  @override
  State<SphotLocalLegalDraftCard> createState() =>
      _SphotLocalLegalDraftCardState();
}

class _SphotLocalLegalDraftCardState
    extends State<SphotLocalLegalDraftCard> {
  static const Color _blue = Color(0xFF1E3A8A);
  static const Color _amber = Color(0xFF9A3412);

  late Future<String> _source;

  @override
  void initState() {
    super.initState();
    _source = rootBundle.loadString(widget.assetPath);
  }

  @override
  void didUpdateWidget(covariant SphotLocalLegalDraftCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _source = rootBundle.loadString(widget.assetPath);
    }
  }

  Future<void> _openPreview() async {
    if (!SphotLocalLegalDraftCard.available) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 18,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SizedBox(
              width: 960,
              height: MediaQuery.sizeOf(dialogContext).height * 0.88,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
                    color: _blue,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.menu_book_outlined,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.documentTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fermer le document',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    color: const Color(0xFFFFF3E0),
                    child: Text(
                      'BROUILLON ${widget.version} — APERÇU LOCAL DE TEST — '
                      'DOCUMENT NON PUBLIÉ',
                      style: const TextStyle(
                        color: _amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<String>(
                      future: _source,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(
                            child: Text(
                              'Le brouillon local n’a pas pu être chargé.',
                              style: TextStyle(color: _amber),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: _LegalDraftFormattedBody(
                            source: snapshot.data!,
                          ),
                        );
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 9, 18, 12),
                    child: Text(
                      'Consultation uniquement : aucune acceptation '
                      'contractuelle, commande ou paiement.',
                      style: TextStyle(
                        color: _blue,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!SphotLocalLegalDraftCard.available) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'BROUILLON ${widget.version} — APERÇU LOCAL, NON PUBLIÉ',
          style: const TextStyle(
            color: _amber,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _openPreview,
          icon: const Icon(Icons.menu_book_outlined, size: 17),
          label: Text('CONSULTER LES ${widget.documentTitle.toUpperCase()}'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _blue,
            alignment: Alignment.centerLeft,
            side: const BorderSide(color: _blue),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }
}

/// Conserve le rendu des paragraphes (dont les passages en gras), mais
/// donne une véritable hiérarchie visuelle aux titres Markdown des articles.
class _LegalDraftFormattedBody extends StatelessWidget {
  const _LegalDraftFormattedBody({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];
    final paragraphs = StringBuffer();
    final headingPattern = RegExp(r'^(#{1,3})\s+(.+)$');

    void flushParagraphs() {
      final text = paragraphs.toString().trim();
      paragraphs.clear();
      if (text.isEmpty) return;
      sections.add(SphotLegalMarkdownPreview(source: text));
    }

    for (final line in source.split(RegExp(r'\r?\n'))) {
      final heading = headingPattern.firstMatch(line);
      if (heading == null) {
        paragraphs.writeln(line);
        continue;
      }

      flushParagraphs();
      final level = heading.group(1)!.length;
      sections.add(Padding(
        padding: EdgeInsets.only(
          top: level == 1 ? 0 : 18,
          bottom: level == 1 ? 12 : 9,
        ),
        child: Text(
          heading.group(2)!.trim(),
          style: TextStyle(
            color: const Color(0xFF1E3A8A),
            fontSize: level == 1 ? 21 : (level == 2 ? 16 : 14),
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
      ));
    }
    flushParagraphs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }
}
