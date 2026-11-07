import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Présentation unifiée des sept sources juridiques SPHOT.
/// Les documents communs sont référencés, jamais recopiés par public.
/// La modification des documents actifs reste volontairement désactivée
/// jusqu'à la validation des règles Firestore et du circuit de publication.
class SuperAdminLegalAudiencePanel extends StatelessWidget {
  const SuperAdminLegalAudiencePanel({super.key});

  static const _blue = Color(0xFF213F8E);
  static const _red = Color(0xFFE52525);

  static const _audiences = <_LegalAudience>[
    _LegalAudience('GRAND PUBLIC', [
      _LegalSection('CGU', [_LegalTarget('CGU — GRAND PUBLIC', 'cgu')]),
      _LegalSection('RGPD', [
        _LegalTarget('NOTICE RGPD', 'rgpdNotice'),
        _LegalTarget('POLITIQUE DE CONFIDENTIALITÉ', 'privacyPolicy'),
      ]),
    ]),
    _LegalAudience('SPHOT ADMIN', [
      _LegalSection('CGU', [_LegalTarget('CGU COMMUNES', 'cgu')]),
      _LegalSection('CGV', [_LegalTarget('CGV — SPHOT ADMIN', 'adminCgv')]),
      _LegalSection('RGPD', [
        _LegalTarget('NOTICE RGPD', 'rgpdNotice'),
        _LegalTarget('POLITIQUE DE CONFIDENTIALITÉ', 'privacyPolicy'),
      ]),
    ]),
    _LegalAudience('SPHOT SAUVETEUR', [
      _LegalSection('CGU', [_LegalTarget('CGU — SPHOT SAUVETEUR', 'sauveteurCgu')]),
      _LegalSection('CHARTE', [
        _LegalTarget('CHARTE — SPHOT SAUVETEUR', 'sauveteurCharter'),
      ]),
      _LegalSection('RGPD', [
        _LegalTarget('NOTICE RGPD', 'rgpdNotice'),
        _LegalTarget('POLITIQUE DE CONFIDENTIALITÉ', 'privacyPolicy'),
      ]),
    ]),
    _LegalAudience('SPHOT PUBLICITAIRE', [
      _LegalSection('CGU', [_LegalTarget('CGU COMMUNES', 'cgu')]),
      _LegalSection('CGV', [
        _LegalTarget('CGV — SPHOT PUBLICITAIRE', 'advertiserCgv'),
      ]),
      _LegalSection('RGPD', [
        _LegalTarget('NOTICE RGPD', 'rgpdNotice'),
        _LegalTarget('POLITIQUE DE CONFIDENTIALITÉ', 'privacyPolicy'),
      ]),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choisissez un public, puis un document. Chaque texte dispose de '
          'ses articles, de sa version et de son historique.',
          style: TextStyle(color: _blue, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        for (final audience in _audiences) ...[
          Container(
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.055),
              border: Border.all(color: _blue, width: 1.4),
              borderRadius: BorderRadius.circular(15),
            ),
            child: ExpansionTile(
              key: PageStorageKey('legal-audience-${audience.name}'),
              shape: const Border(),
              collapsedShape: const Border(),
              iconColor: _red,
              collapsedIconColor: _red,
              title: Text(audience.name,
                  style: const TextStyle(color: _red,
                      fontSize: 15, fontWeight: FontWeight.w900)),
              childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              children: [
                for (final section in audience.sections)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _blue.withOpacity(0.65)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ExpansionTile(
                        key: PageStorageKey(
                            'legal-section-${audience.name}-${section.name}'),
                        shape: const Border(),
                        collapsedShape: const Border(),
                        iconColor: _red,
                        collapsedIconColor: _red,
                        title: Text(section.name,
                            style: const TextStyle(color: _blue,
                                fontSize: 14, fontWeight: FontWeight.w900)),
                        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        children: [
                          for (final target in section.targets)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _LegalDocumentCard(
                                key: ValueKey(
                                    '${audience.name}-${target.documentId}'),
                                title: target.title,
                                documentId: target.documentId,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _LegalAudience {
  const _LegalAudience(this.name, this.sections);
  final String name;
  final List<_LegalSection> sections;
}

class _LegalSection {
  const _LegalSection(this.name, this.targets);
  final String name;
  final List<_LegalTarget> targets;
}

class _LegalTarget {
  const _LegalTarget(this.title, this.documentId);
  final String title;
  final String documentId;
}

class _LegalArticle {
  const _LegalArticle({required this.id, required this.title,
    required this.content, required this.order});
  final String id;
  final String title;
  final String content;
  final int order;

  Map<String, dynamic> toMap() => {
    'id': id, 'title': title, 'content': content,
    'order': order, 'isActive': true,
  };
}

class _LegalData {
  const _LegalData({required this.articles, required this.version,
    required this.revision, required this.prepared,
    required this.preparedStatus, required this.history, required this.updatedAt});
  final List<_LegalArticle> articles;
  final String version;
  final int revision;
  final bool prepared;
  final String preparedStatus;
  final List<Map<String, dynamic>> history;
  final DateTime? updatedAt;
}

class _LegalDocumentCard extends StatefulWidget {
  const _LegalDocumentCard({super.key, required this.title,
    required this.documentId});
  final String title;
  final String documentId;

  @override
  State<_LegalDocumentCard> createState() => _LegalDocumentCardState();
}

class _LegalDocumentCardState extends State<_LegalDocumentCard> {
  static const _blue = Color(0xFF213F8E);
  static const _red = Color(0xFFE52525);

  // Aucun enregistrement de production avant sécurisation des règles et accord.
  static const _editingEnabled = bool.fromEnvironment(
    'SPHOT_LEGAL_ARTICLE_EDIT', defaultValue: false);
  static const _preparedIds = <String>{
    'cgu', 'adminCgv', 'advertiserCgv', 'sauveteurCgu', 'sauveteurCharter',
  };
  static const _validatedAssets = <String, String>{
    'cgu': 'assets/legal/test_corpus/cgu_grand_public.md',
    'adminCgv': 'assets/legal/test_corpus/cgv_admin.md',
    'advertiserCgv': 'assets/legal/test_corpus/cgv_publicitaire.md',
    'sauveteurCgu': 'assets/legal/test_corpus/cgu_sauveteur.md',
    'sauveteurCharter': 'assets/legal/test_corpus/charte_sauveteur.md',
  };

  late Future<_LegalData> _future;
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _changeSummary = TextEditingController();
  String? _selectedArticleId;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _changeSummary.dispose();
    super.dispose();
  }

  static String _string(dynamic value) => value?.toString().trim() ?? '';

  static List<_LegalArticle> _articlesFromList(dynamic source) {
    if (source is! List) return const [];
    final articles = <_LegalArticle>[];
    for (var i = 0; i < source.length; i++) {
      final raw = source[i];
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final title = _string(item['title'] ?? item['titre']);
      final content = _string(item['content'] ?? item['texte']);
      if (title.isEmpty || content.isEmpty) continue;
      articles.add(_LegalArticle(
        id: _string(item['id']).isEmpty ? '${i + 1}'.padLeft(2, '0')
            : _string(item['id']),
        title: title, content: content,
        order: item['order'] is int ? item['order'] as int : i + 1,
      ));
    }
    articles.sort((a, b) => a.order.compareTo(b.order));
    return articles;
  }

  /// Repli local en lecture seule : les cinq fichiers correspondent aux
  /// contenus déjà vérifiés. Ils ne remplacent jamais un document publié.
  static Future<List<_LegalArticle>> _validatedBundle(String documentId) async {
    final path = _validatedAssets[documentId];
    if (path == null) return const [];
    final markdown = await rootBundle.loadString(path);
    final headings = RegExp(r'^##\s+(.+)$', multiLine: true)
        .allMatches(markdown).toList();
    final result = <_LegalArticle>[];
    for (var i = 0; i < headings.length; i++) {
      final heading = headings[i];
      final end = i + 1 < headings.length
          ? headings[i + 1].start : markdown.length;
      final title = (heading.group(1) ?? '').trim();
      final content = markdown.substring(heading.end, end).trim();
      if (title.isEmpty || content.isEmpty) continue;
      result.add(_LegalArticle(
        id: '${i + 1}'.padLeft(2, '0'), title: title,
        content: content, order: i + 1,
      ));
    }
    return result;
  }

  Future<_LegalData> _load() async {
    final firestore = FirebaseFirestore.instance;
    final ref = firestore.collection('legalDocuments').doc(widget.documentId);
    final live = await ref.get();
    final liveData = live.data() ?? <String, dynamic>{};
    final chapters = await ref.collection('chapters').get();
    var articles = _articlesFromList(liveData['chapters']);
    if (chapters.docs.isNotEmpty) {
      articles = _articlesFromList(chapters.docs.map((doc) => {
        'id': doc.id, ...doc.data(),
      }).toList());
    }
    var prepared = false;
    var preparedStatus = '';
    var version = _string(liveData['version']);
    var revision = liveData['revision'] is int
        ? liveData['revision'] as int : 0;
    final publishedFinal = liveData['published'] == true &&
        _string(liveData['publicationSource']) ==
            'legal_pack_five_documents_atomic_v1';
    if (_preparedIds.contains(widget.documentId) && !publishedFinal) {
      try {
        final pending = await firestore.collection('legalDocumentDrafts')
            .doc(widget.documentId).get();
        final candidate = pending.data();
        if (candidate != null &&
            _string(candidate['status']) != 'published' &&
            candidate['chapters'] is List) {
          final finalArticles = _articlesFromList(candidate['chapters']);
          if (finalArticles.isNotEmpty) {
            articles = finalArticles;
            prepared = true;
            preparedStatus = _string(candidate['status']);
            version = _string(candidate['sourceVersion']).isEmpty
                ? version : _string(candidate['sourceVersion']);
          }
        }
      } on FirebaseException {
        // Si l'accès aux textes préparés est restreint, le texte actif reste
        // disponible. Le repli local n'écrit jamais dans Firestore.
      }
      if (!prepared) {
        try {
          final bundled = await _validatedBundle(widget.documentId);
          if (bundled.isNotEmpty) {
            articles = bundled;
            prepared = true;
            preparedStatus = 'localValidated';
          }
        } on FlutterError {
          // Conserver le document actif s'il manque un fichier embarqué.
        }
      }
    }
    final history = <Map<String, dynamic>>[];
    try {
      final prior = await firestore.collection('legalVersions')
          .where('documentId', isEqualTo: widget.documentId).get();
      for (final item in prior.docs) {
        history.add({'id': item.id, ...item.data()});
      }
      // L'ancien panneau conservait les trois textes communs dans une
      // version globale 1_0. Elle reste visible dans le nouvel historique.
      if (widget.documentId == 'cgu' ||
          widget.documentId == 'privacyPolicy' ||
          widget.documentId == 'rgpdNotice') {
        final global = await firestore.collection('legalVersions')
            .doc('1_0').get();
        final globalData = global.data();
        final snapshots = globalData?['documents'];
        if (snapshots is Map && snapshots[widget.documentId] is Map &&
            !history.any((item) => item['id'] == '1_0')) {
          final old = Map<String, dynamic>.from(snapshots[widget.documentId]);
          final doc = old['document'];
          final root = doc is Map ? Map<String, dynamic>.from(doc) :
              <String, dynamic>{};
          history.add({
            'id': '1_0',
            'documentId': widget.documentId,
            'version': _string(globalData?['version']),
            'revision': root['revision'] ?? 0,
            'status': _string(globalData?['status']),
          });
        }
      }
      history.sort((a, b) => ((b['revision'] as num?)?.toInt() ?? -1)
          .compareTo((a['revision'] as num?)?.toInt() ?? -1));
    } on FirebaseException {
      // L'historique peut avoir des droits de lecture distincts.
    }
    return _LegalData(
      articles: articles,
      version: version.isEmpty ? '1.0' : version,
      revision: revision,
      prepared: prepared,
      preparedStatus: preparedStatus,
      history: history,
      updatedAt: (liveData['updatedAt'] is Timestamp)
          ? (liveData['updatedAt'] as Timestamp).toDate() : null,
    );
  }

  void _choose(_LegalArticle article) {
    setState(() {
      _selectedArticleId = article.id;
      _title.text = article.title;
      _content.text = article.content;
      _changeSummary.clear();
      _message = null;
    });
  }

  Future<void> _save(_LegalData data) async {
    if (!_editingEnabled || data.prepared || _saving ||
        _selectedArticleId == null ||
        _title.text.trim().isEmpty || _content.text.trim().isEmpty ||
        _changeSummary.text.trim().isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Le simple affichage du tableau de bord ne suffit pas à autoriser une
    // écriture. Le serveur doit avoir émis des claims Super Admin non expirés.
    final token = await user.getIdTokenResult(true);
    final claims = token.claims ?? const <String, dynamic>{};
    final expiresAt = claims['sphotSaSessionExpiresAt'];
    final expiresMillis = expiresAt is num ? expiresAt.toInt() : 0;
    if (claims['role'] != 'SPHOT_SUPER_ADMIN' ||
        claims['sphotSuperAdmin'] != true ||
        expiresMillis <= DateTime.now().millisecondsSinceEpoch) {
      if (mounted) setState(() => _message =
          'Session Super Admin certifiée requise pour enregistrer.');
      return;
    }
    final confirmed = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('NOUVELLE RÉVISION JURIDIQUE'),
        content: Text('Cette action modifie immédiatement le document actif '
            '${widget.title}, conserve la révision précédente et peut '
            'nécessiter une nouvelle acceptation par les utilisateurs. '
            'Confirmer l’enregistrement ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ANNULER')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('ENREGISTRER LA RÉVISION')),
        ],
      ),
    ) == true;
    if (!confirmed || !mounted) return;
    setState(() { _saving = true; _message = null; });
    try {
      final firestore = FirebaseFirestore.instance;
      final ref = firestore.collection('legalDocuments').doc(widget.documentId);
      final oldRevision = data.revision;
      final nextRevision = oldRevision + 1;
      final id = _selectedArticleId!;
      final nextArticles = data.articles.map((article) => article.id == id
          ? _LegalArticle(id: id, title: _title.text.trim(),
              content: _content.text.trim(), order: article.order)
          : article).toList();
      final priorRef = firestore.collection('legalVersions').doc(
          '${widget.documentId}_r${'$oldRevision'.padLeft(8, '0')}_before_edit');
      final nextRef = firestore.collection('legalVersions').doc(
          '${widget.documentId}_r${'$nextRevision'.padLeft(8, '0')}_edited');
      await firestore.runTransaction((tx) async {
        final current = await tx.get(ref);
        final prior = await tx.get(priorRef);
        final next = await tx.get(nextRef);
        if (!current.exists || current.data()?['revision'] != oldRevision ||
            next.exists) {
          throw StateError('Le document a changé : rechargez sa version.');
        }
        if (!prior.exists) {
          tx.set(priorRef, {
            'documentId': widget.documentId, 'version': data.version,
            'revision': oldRevision, 'status': 'Historique',
            'chapters': data.articles.map((a) => a.toMap()).toList(),
            'archivedByUid': user.uid,
            'archivedAt': FieldValue.serverTimestamp(),
          });
        }
        tx.set(nextRef, {
          'documentId': widget.documentId, 'version': data.version,
          'revision': nextRevision, 'status': 'Publié',
          'chapters': nextArticles.map((a) => a.toMap()).toList(),
          'changeLog': _changeSummary.text.trim(),
          'publishedByUid': user.uid,
          'publishedAt': FieldValue.serverTimestamp(),
        });
        tx.set(ref, {
          'revision': nextRevision,
          'chapters': nextArticles.map((a) => a.toMap()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        final changed = nextArticles.firstWhere((a) => a.id == id);
        tx.set(ref.collection('chapters').doc(id), {
          'title': changed.title, 'content': changed.content,
          'order': changed.order, 'isActive': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      if (!mounted) return;
      setState(() {
        _future = _load();
        _selectedArticleId = null;
        _message = 'Nouvelle révision enregistrée.';
      });
    } catch (error) {
      if (mounted) setState(() => _message =
          'Enregistrement non confirmé : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LegalData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(color: _blue));
        }
        if (snapshot.hasError) {
          return Text('Document indisponible : ${snapshot.error}',
              style: const TextStyle(color: _red, fontSize: 12));
        }
        final data = snapshot.data!;
        return Container(
          decoration: BoxDecoration(
            color: _blue.withOpacity(0.035),
            border: Border.all(color: _blue.withOpacity(0.45)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ExpansionTile(
            key: PageStorageKey('legal-document-${widget.key}'),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(widget.title,
                style: const TextStyle(color: _blue, fontWeight: FontWeight.w800,
                    fontSize: 12)),
            subtitle: Text(data.prepared
                ? '${data.articles.length} articles · Texte final non publié'
                : '${data.articles.length} articles · Version active ${data.version}',
                style: const TextStyle(color: _red, fontSize: 11)),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            children: [
              if (data.articles.isEmpty)
                const Padding(padding: EdgeInsets.all(10),
                  child: Text('Aucun article disponible.')),
              for (final article in data.articles)
                ExpansionTile(
                  key: PageStorageKey('legal-article-${widget.key}-${article.id}'),
                  title: Text(article.title,
                      style: const TextStyle(color: _blue, fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  childrenPadding: const EdgeInsets.all(10),
                  children: [
                    SelectableText(article.content,
                        style: const TextStyle(fontSize: 12, height: 1.45)),
                    Align(alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: data.prepared || !_editingEnabled
                            ? null : () => _choose(article),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('MODIFIER CET ARTICLE'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              _versionPanel(data),
            ],
          ),
        );
      },
    );
  }

  Widget _versionPanel(_LegalData data) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _red.withOpacity(0.65)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('VERSION', style: TextStyle(color: _red,
            fontWeight: FontWeight.w900, fontSize: 14)),
        const SizedBox(height: 6),
        Text('Document : ${widget.title}',
            style: const TextStyle(color: _blue, fontSize: 12)),
        Text('Version ${data.version} · Révision active ${data.revision}',
            style: const TextStyle(color: _blue, fontSize: 12)),
        Text(data.prepared
            ? (data.preparedStatus == 'validated'
                ? 'Texte validé — publication non effectuée'
                : 'Texte préparé — publication non effectuée')
            : 'Texte actuellement enregistré dans Firestore',
            style: const TextStyle(color: _red, fontSize: 11)),
        if (data.updatedAt != null)
          Text('Dernière mise à jour : ${data.updatedAt!.day.toString().padLeft(2, '0')}/'
              '${data.updatedAt!.month.toString().padLeft(2, '0')}/'
              '${data.updatedAt!.year}',
              style: const TextStyle(color: _blue, fontSize: 11)),
        if (_selectedArticleId != null && !data.prepared) ...[
          const SizedBox(height: 10),
          TextField(controller: _title,
              decoration: const InputDecoration(labelText: 'Titre de l’article',
                  border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _content, minLines: 5, maxLines: 12,
              decoration: const InputDecoration(labelText: 'Contenu de l’article',
                  alignLabelWithHint: true, border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _changeSummary, minLines: 2, maxLines: 4,
              decoration: const InputDecoration(labelText: 'Résumé des modifications',
                  border: OutlineInputBorder())),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _saving ? null : () => _save(data),
              icon: const Icon(Icons.save_outlined),
              label: const Text('ENREGISTRER UNE NOUVELLE RÉVISION')),
        ],
        if (!_editingEnabled)
          const Padding(padding: EdgeInsets.only(top: 8),
            child: Text('Édition sécurisée désactivée jusqu’à validation '
                'des règles Firestore et du circuit de publication.',
                style: TextStyle(color: _red, fontSize: 11))),
        const SizedBox(height: 10),
        ExpansionTile(
          shape: const Border(), collapsedShape: const Border(),
          title: const Text('HISTORIQUE DES VERSIONS',
              style: TextStyle(color: _blue, fontSize: 12,
                  fontWeight: FontWeight.w800)),
          children: data.history.isEmpty
              ? [const ListTile(dense: true,
                  title: Text('Aucune version individuelle disponible.'))]
              : data.history.map((entry) => ListTile(
                  dense: true,
                  title: Text('Révision ${entry['revision'] ?? '?'} · '
                      '${entry['version'] ?? data.version}',
                      style: const TextStyle(fontSize: 12)),
                  subtitle: Text(_string(entry['status']),
                      style: const TextStyle(fontSize: 11)),
                )).toList(),
        ),
        if (_message != null)
          Text(_message!, style: const TextStyle(color: _red, fontSize: 11)),
      ]),
    );
  }
}
