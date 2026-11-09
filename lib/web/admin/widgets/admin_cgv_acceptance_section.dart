import 'package:flutter/material.dart';

import '../../super_admin/widgets/sphot_legal_article_markdown.dart';
import '../services/admin_cgv_live_service.dart';

/// Consultation des seules CGV ADMIN officiellement publiées.
/// La case est une préparation locale : l'acceptation contractuelle et sa
/// preuve seront enregistrées par le serveur lors d'une future commande.
class AdminCgvAcceptanceSection extends StatefulWidget {
  const AdminCgvAcceptanceSection({
    super.key,
    this.documentStream,
  });

  /// Injection facultative pour tester l'interface sans accès Firebase.
  final Stream<AdminCgvLiveDocument>? documentStream;

  @override
  State<AdminCgvAcceptanceSection> createState() =>
      _AdminCgvAcceptanceSectionState();
}

class _AdminCgvAcceptanceSectionState extends State<AdminCgvAcceptanceSection> {
  static const _grey = Color(0xFF6B7280);

  late Stream<AdminCgvLiveDocument> _documents;

  @override
  void initState() {
    super.initState();
    _documents = widget.documentStream ?? AdminCgvLiveService.watchPublished();
  }

  @override
  void didUpdateWidget(covariant AdminCgvAcceptanceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentStream != widget.documentStream) {
      _documents = widget.documentStream ?? AdminCgvLiveService.watchPublished();
    }
  }

  void _reload() {
    setState(() {
      _documents = widget.documentStream ?? AdminCgvLiveService.watchPublished();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminCgvLiveDocument>(
      stream: _documents,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Les CGV SPHOT Admin officiellement publiées ne sont pas '
                'disponibles. Aucune acceptation ne peut être recueillie.',
                style: TextStyle(color: _grey, fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 7),
              TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('RÉESSAYER'),
              ),
            ],
          );
        }

        if (!snapshot.hasData) {
          return const Row(
            children: [
              SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Expanded(child: Text('Chargement des CGV publiées…',
                style: TextStyle(color: _grey, fontSize: 11))),
            ],
          );
        }

        final document = snapshot.requireData;
        return _PublishedAdminCgv(
          key: ValueKey(document.presentationSignature),
          document: document,
        );
      },
    );
  }
}

class _PublishedAdminCgv extends StatefulWidget {
  const _PublishedAdminCgv({super.key, required this.document});

  final AdminCgvLiveDocument document;

  @override
  State<_PublishedAdminCgv> createState() => _PublishedAdminCgvState();
}

class _PublishedAdminCgvState extends State<_PublishedAdminCgv> {
  static const _blue = Color(0xFF1E3A8A);
  static const _grey = Color(0xFF6B7280);
  static const _green = Color(0xFF16A34A);

  bool _consulted = false;
  bool _checked = false;

  Future<void> _consult() async {
    final document = widget.document;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: SizedBox(
            width: size.width > 860 ? 820 : size.width - 28,
            height: size.height * 0.83,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CONDITIONS GÉNÉRALES DE VENTE — SPHOT ADMIN',
                    style: TextStyle(color: _blue, fontSize: 15,
                      fontWeight: FontWeight.w900)),
                  const SizedBox(height: 7),
                  Text(_versionLabel(dialogContext, document),
                    style: const TextStyle(color: _grey, fontSize: 12)),
                  const Divider(height: 24),
                  Expanded(
                    child: ListView.separated(
                      itemCount: document.chapters.length,
                      separatorBuilder: (_, _) => const Divider(height: 26),
                      itemBuilder: (context, index) {
                        final chapter = document.chapters[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(chapter.title,
                              style: const TextStyle(color: _blue,
                                fontSize: 13, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 9),
                            SphotLegalArticleMarkdown(markdown: chapter.content),
                          ],
                        );
                      },
                    ),
                  ),
                  const Divider(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('FERMER'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (mounted) setState(() => _consulted = true);
  }

  static String _versionLabel(BuildContext context, AdminCgvLiveDocument doc) {
    final date = doc.publishedAt == null
        ? ''
        : ' · Publiées le ${MaterialLocalizations.of(context).formatMediumDate(doc.publishedAt!)}';
    return 'Version ${doc.version} · Révision ${doc.revision}$date';
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_versionLabel(context, document),
          style: const TextStyle(color: _grey, fontSize: 11)),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: _consult,
          icon: const Icon(Icons.menu_book_outlined, size: 18),
          label: Text('CONSULTER LES ${document.chapters.length} ARTICLES',
            style: const TextStyle(fontSize: 11,
              fontWeight: FontWeight.w800)),
          style: OutlinedButton.styleFrom(
            foregroundColor: _blue,
            side: const BorderSide(color: _blue),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          ),
        ),
        const SizedBox(height: 7),
        CheckboxListTile(
          value: _checked,
          onChanged: _consulted
              ? (checked) => setState(() => _checked = checked ?? false)
              : null,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeColor: _green,
          title: Text(
            'Je reconnais avoir pris connaissance des Conditions Générales '
            'de Vente SPHOT Admin (version ${document.versionId}) et '
            'les accepte expressément.',
            style: const TextStyle(fontSize: 11, height: 1.35),
          ),
        ),
        if (!_consulted)
          const Text('Consultez le document avant de cocher cette case.',
            style: TextStyle(color: _grey, fontSize: 10)),
        const SizedBox(height: 5),
        const Text(
          'Sélection temporaire à cette étape : aucune acceptation '
          'contractuelle ni commande n’est enregistrée avant la validation '
          'sécurisée côté serveur.',
          style: TextStyle(color: _grey, fontSize: 10, height: 1.35),
        ),
      ],
    );
  }
}
