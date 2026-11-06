import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../web/super_admin/widgets/sphot_legal_markdown_preview.dart';

/// Consultation d'un document juridique depuis sa référence Firestore unique.
/// L'affichage n'enregistre aucune acceptation et n'engage aucune commande.
class SphotLegalDocumentCard extends StatefulWidget {
  const SphotLegalDocumentCard({
    super.key,
    required this.documentId,
    required this.title,
    this.initiallyExpanded = false,
  });

  final String documentId;
  final String title;
  final bool initiallyExpanded;

  @override
  State<SphotLegalDocumentCard> createState() =>
      _SphotLegalDocumentCardState();
}

class _SphotLegalDocumentCardState extends State<SphotLegalDocumentCard> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    final document = FirebaseFirestore.instance
        .collection('legalDocuments')
        .doc(widget.documentId);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue, width: 1.4),
      ),
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: _red,
        collapsedIconColor: _red,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        title: Text(widget.title,
            style: const TextStyle(
              color: _blue,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            )),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: document.snapshots(),
              builder: (context, documentSnapshot) {
                if (documentSnapshot.hasError) {
                  return const Text('Document momentanément indisponible.',
                      style: TextStyle(color: _red));
                }
                if (!documentSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = documentSnapshot.data!.data() ??
                    <String, dynamic>{};
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: document.collection('chapters')
                      .orderBy(FieldPath.documentId).snapshots(),
                  builder: (context, chaptersSnapshot) {
                    if (chaptersSnapshot.hasError) {
                      return const Text('Articles momentanément indisponibles.',
                          style: TextStyle(color: _red));
                    }
                    if (!chaptersSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final parentChapters = data['chapters'] is List
                        ? data['chapters'] as List : <dynamic>[];
                    // Les CGV PUBLICITAIRE sont enregistrées dans le parent :
                    // ne jamais afficher une ancienne sous-collection à la
                    // place des articles réellement acceptés par l'annonceur.
                    final chapters = widget.documentId == 'advertiserCgv'
                        ? parentChapters
                        : (chaptersSnapshot.data!.docs.isNotEmpty
                            ? chaptersSnapshot.data!.docs
                                .map((item) => item.data()).toList()
                            : parentChapters);
                    if (chapters.isEmpty || data['published'] == false) {
                      return const Text('Document temporairement indisponible.',
                          style: TextStyle(color: _blue));
                    }
                    final version = (data['version'] ?? '1.0').toString();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...chapters.whereType<Map>().map((raw) {
                          final chapter = Map<String, dynamic>.from(raw);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text((chapter['title'] ?? chapter['titre'] ?? '')
                                    .toString(),
                                    style: const TextStyle(
                                      color: _red,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    )),
                                const SizedBox(height: 5),
                                SphotLegalMarkdownPreview(
                                  source: (chapter['content'] ??
                                          chapter['texte'] ?? '')
                                      .toString(),
                                  bodyStyle: const TextStyle(
                                    color: _blue,
                                    fontSize: 12,
                                    height: 1.35,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        Text('Version SPHOT $version — consultation uniquement',
                            style: const TextStyle(
                              color: _blue,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            )),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
