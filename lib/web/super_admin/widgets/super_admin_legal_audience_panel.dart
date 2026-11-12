import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'sphot_legal_article_markdown.dart';

/// Présentation unifiée des neuf documents juridiques SPHOT.
/// Les documents communs sont référencés, jamais recopiés par public.
/// Edition des brouillons par une fonction serveur Super Admin uniquement.
/// Aucun acces en ecriture directe aux documents juridiques depuis Flutter.
class SuperAdminLegalAudiencePanel extends StatelessWidget {
  const SuperAdminLegalAudiencePanel({super.key});

  static const _blue = Color(0xFF213F8E);

  static const _audiences = <_LegalAudience>[
    _LegalAudience('GRAND PUBLIC', [
      _LegalSection('CGU', [_LegalTarget('CGU — GRAND PUBLIC', 'cgu')]),
    ]),
    _LegalAudience('SPHOT ADMIN', [
      _LegalSection('CGU', [_LegalTarget('CGU — SPHOT ADMIN', 'adminCgu')]),
      _LegalSection('CGV', [_LegalTarget('CGV — SPHOT ADMIN', 'adminCgv')]),
    ]),
    _LegalAudience('SPHOT SAUVETEUR', [
      _LegalSection('CGU', [_LegalTarget('CGU — SPHOT SAUVETEUR', 'sauveteurCgu')]),
      _LegalSection('CHARTE', [
        _LegalTarget('CHARTE — SPHOT SAUVETEUR', 'sauveteurCharter'),
      ]),
    ]),
    _LegalAudience('SPHOT PUBLICITAIRE', [
      _LegalSection('CGU', [_LegalTarget('CGU — SPHOT PUBLICITAIRE', 'advertiserCgu')]),
      _LegalSection('CGV', [
        _LegalTarget('CGV — SPHOT PUBLICITAIRE', 'advertiserCgv'),
      ]),
    ]),
    _LegalAudience('NOTICE RGPD', [],
        commonDocument: _LegalTarget('NOTICE RGPD', 'rgpdNotice')),
    _LegalAudience('POLITIQUE DE CONFIDENTIALITÉ', [],
        commonDocument: _LegalTarget(
            'POLITIQUE DE CONFIDENTIALITÉ', 'privacyPolicy')),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choisissez une rubrique juridique. Chaque document dispose de '
          'ses articles, de sa version et de son historique.',
          style: TextStyle(color: _blue, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        for (final audience in _audiences) ...[
          _LegalAudienceCard(key: ValueKey(audience.name), audience: audience),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _LegalAudience {
  const _LegalAudience(this.name, this.sections, {this.commonDocument});
  final String name;
  final List<_LegalSection> sections;
  final _LegalTarget? commonDocument;
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

/// Construit les lectures Firestore uniquement après ouverture d'une rubrique.
/// Les documents n'entrainent pas de chargements initiaux inutiles.
class _LegalAudienceCard extends StatefulWidget {
  const _LegalAudienceCard({super.key, required this.audience});
  final _LegalAudience audience;

  @override
  State<_LegalAudienceCard> createState() => _LegalAudienceCardState();
}

class _LegalAudienceCardState extends State<_LegalAudienceCard> {
  static const _blue = Color(0xFF213F8E);
  static const _red = Color(0xFFE52525);
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _blue.withValues(alpha: 0.055),
      border: Border.all(color: _blue, width: 1.4),
      borderRadius: BorderRadius.circular(15),
    ),
    child: ExpansionTile(
      onExpansionChanged: (value) => setState(() => _expanded = value),
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: _red,
      collapsedIconColor: _red,
      title: Text(widget.audience.name,
          style: const TextStyle(color: _red, fontSize: 15,
              fontWeight: FontWeight.w900)),
      childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      children: _expanded
          ? [for (final section in widget.audience.sections)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _LegalSectionCard(
                  key: ValueKey(section.name),
                  section: section,
                  audienceName: widget.audience.name,
                ),
              ),
              if (widget.audience.commonDocument != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _LegalDocumentCard(
                    key: ValueKey(
                        'common-${widget.audience.commonDocument!.documentId}'),
                    title: widget.audience.commonDocument!.title,
                    documentId: widget.audience.commonDocument!.documentId,
                  ),
                ),
            ]
          : const [],
    ),
  );
}

class _LegalSectionCard extends StatefulWidget {
  const _LegalSectionCard({super.key, required this.section,
    required this.audienceName});
  final _LegalSection section;
  final String audienceName;

  @override
  State<_LegalSectionCard> createState() => _LegalSectionCardState();
}

class _LegalSectionCardState extends State<_LegalSectionCard> {
  static const _blue = Color(0xFF213F8E);
  static const _red = Color(0xFFE52525);
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _blue.withValues(alpha: 0.65)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: ExpansionTile(
      onExpansionChanged: (value) => setState(() => _expanded = value),
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: _red,
      collapsedIconColor: _red,
      title: Text(widget.section.name,
          style: const TextStyle(color: _blue, fontSize: 14,
              fontWeight: FontWeight.w900)),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: _expanded
          ? [for (final target in widget.section.targets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LegalDocumentCard(
                  key: ValueKey('${widget.audienceName}-${target.documentId}'),
                  title: target.title,
                  documentId: target.documentId,
                ),
              ),
            ]
          : const [],
    ),
  );
}

class _LegalArticle {
  const _LegalArticle({required this.id, required this.title,
    required this.content, required this.order});
  final String id;
  final String title;
  final String content;
  final int order;

}

class _LegalData {
  const _LegalData({required this.articles, required this.version,
    required this.revision, required this.prepared, required this.published,
    required this.history, required this.updatedAt,
    required this.editorDraft, required this.initialPackPublished,
    required this.publicationEnabled, required this.editorError});
  final List<_LegalArticle> articles;
  final String version;
  final int revision;
  final bool prepared;
  final bool published;
  final List<Map<String, dynamic>> history;
  final DateTime? updatedAt;
  final Map<String, dynamic>? editorDraft;
  final bool initialPackPublished;
  final bool publicationEnabled;
  final String? editorError;
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

  // La fonction de modification juridique est deja deployee. L'URL reste
  // strictement verifiee par _editorEndpoint, et chaque operation requiert
  // une authentification Super Admin validee cote serveur.
  static const _configuredEditorUrl = String.fromEnvironment(
    'SPHOT_LEGAL_DOCUMENT_EDITOR_URL',
    defaultValue:
        'https://us-central1-sphot-ab80b.cloudfunctions.net/manageSphotLegalDocumentEditing');
  static Uri? get _editorEndpoint {
    final uri = Uri.tryParse(_configuredEditorUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.hasPort ||
        uri.userInfo.isNotEmpty || uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.host != 'us-central1-sphot-ab80b.cloudfunctions.net' ||
        uri.path != '/manageSphotLegalDocumentEditing') {
      return null;
    }
    return uri;
  }
  static const _preparedIds = <String>{
    'cgu', 'adminCgu', 'advertiserCgu', 'adminCgv', 'advertiserCgv',
    'sauveteurCgu', 'sauveteurCharter',
  };
  static const _validatedAssets = <String, String>{
    'cgu': 'assets/legal/test_corpus/cgu_grand_public.md',
    'adminCgu': 'assets/legal/prepublication_2026_11_11/cgu_admin.md',
    'advertiserCgu': 'assets/legal/prepublication_2026_11_11/cgu_publicitaire.md',
    'adminCgv': 'assets/legal/test_corpus/cgv_admin.md',
    'advertiserCgv': 'assets/legal/test_corpus/cgv_publicitaire.md',
    'sauveteurCgu': 'assets/legal/prepublication_2026_11_11/cgu_sauveteur.md',
    'sauveteurCharter': 'assets/legal/prepublication_2026_11_11/charte_sauveteur.md',
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

  /// Repli local en lecture seule : corpus juridique validé.
  /// L'enregistrement en brouillon passe uniquement par la fonction serveur.
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

  Future<Map<String, dynamic>> _editorRequest(Map<String, dynamic> body) async {
    final url = _editorEndpoint;
    if (url == null) throw StateError('Service sécurisé non activé.');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Connexion Super Admin requise.');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Session Firebase indisponible.');
    }
    final response = await http.post(url, headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    }, body: jsonEncode(body)).timeout(const Duration(seconds: 45));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['success'] != true ||
        response.statusCode != 200) {
      final reason = decoded is Map ? decoded['error']?.toString() : null;
      throw StateError('Opération refusée : ${reason ?? 'service indisponible'}.');
    }
    return Map<String, dynamic>.from(decoded);
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
    var version = _string(liveData['version']);
    var revision = liveData['revision'] is int
        ? liveData['revision'] as int : 0;
    final publicationSource = _string(liveData['publicationSource']);
    final publishedFinal = liveData['published'] == true &&
        (publicationSource == 'legal_pack_five_documents_atomic_v1' ||
         publicationSource == 'sphot_legal_document_editor_v1');
    final professionalUpgrade = _initialProfessionalSections.containsKey(
      widget.documentId) &&
        publicationSource != 'sphot_legal_document_editor_v1';
    if (_preparedIds.contains(widget.documentId) &&
        (!publishedFinal || professionalUpgrade)) {
      // Les documents préparés pour publication ne doivent pas être lus
      // directement dans Firestore : les règles prévues les protègent.
      // Les cinq fichiers embarqués ont déjà été rapprochés de leur corpus
      // validé. Cette consultation n'écrit et ne publie rien.
      try {
        final bundled = await _validatedBundle(widget.documentId);
        if (bundled.isNotEmpty) {
          articles = bundled;
          prepared = true;
        }
      } on FlutterError {
        // Conserver le document actif s'il manque un fichier embarqué.
      }
    }
    Map<String, dynamic>? editorDraft;
    bool initialPackPublished = false;
    bool publicationEnabled = false;
    String? editorError;
    if (_editorEndpoint != null) {
      try {
        final state = await _editorRequest({
          'action': 'status', 'documentId': widget.documentId,
        });
        initialPackPublished = state['initialPackPublished'] == true;
        publicationEnabled = state['publicationEnabled'] == true;
        final draft = state['draft'];
        if (draft is Map &&
            (draft['status'] == 'draft' || draft['status'] == 'validated')) {
          editorDraft = Map<String, dynamic>.from(draft);
          final work = _articlesFromList(editorDraft['chapters']);
          if (work.isNotEmpty) articles = work;
        }
      } catch (error) {
        editorError = error.toString();
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
      published: liveData['published'] == true,
      history: history,
      editorDraft: editorDraft,
      initialPackPublished: initialPackPublished,
      publicationEnabled: publicationEnabled,
      editorError: editorError,
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

  /// Ouvre l'editeur sur le document partage. Si aucun brouillon n'existe,
  /// le cree d'abord sur le serveur, sans toucher au document publie.
  Future<void> _startArticleEdit(_LegalData data, _LegalArticle article) async {
    if (_saving || _editorEndpoint == null || data.editorError != null ||
        !data.initialPackPublished) {
      return;
    }
    if (data.editorDraft != null) {
      _choose(article);
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await _editorRequest({
        'action': 'create',
        'documentId': widget.documentId,
      });
      if (!mounted) return;
      setState(() {
        _selectedArticleId = article.id;
        _title.text = article.title;
        _content.text = article.content;
        _changeSummary.clear();
        _message = 'Modification ouverte. La version publiée reste inchangée.';
        _future = _load();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Édition non ouverte : $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _refresh() {
    setState(() {
      _selectedArticleId = null;
      _message = null;
      _future = _load();
    });
  }

  Future<bool> _confirm(String title, String detail, String action) async {
    return await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ANNULER')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action)),
        ],
      ),
    ) == true;
  }

  Future<void> _runEdit(Map<String, dynamic> request, String success) async {
    if (_saving || _editorEndpoint == null) return;
    setState(() { _saving = true; _message = null; });
    try {
      await _editorRequest({'documentId': widget.documentId, ...request});
      if (!mounted) return;
      setState(() {
        _future = _load();
        _selectedArticleId = null;
        _message = success;
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Opération non enregistrée : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _initialProfessionalSections = <String, int>{
    'adminCgu': 14,
    'advertiserCgu': 12,
    'sauveteurCgu': 8,
    'sauveteurCharter': 7,
  };

  /// Enregistre les textes approuvés dans Firestore via l'éditeur sécurisé :
  /// legalEditorialDrafts/{documentId}, sans changer legalDocuments.
  Future<void> _registerApprovedDraft(_LegalData data) async {
    final expectedCount = _initialProfessionalSections[widget.documentId];
    if (_saving || expectedCount == null ||
        data.editorDraft != null || !data.initialPackPublished ||
        data.editorError != null || _editorEndpoint == null ||
        data.articles.length != expectedCount || !data.prepared) {
      return;
    }
    final confirmed = await _confirm(
      'ENREGISTRER DANS FIREBASE ?',
      'Les $expectedCount articles ou rubriques approuvés de '
      '${widget.title} seront enregistrés dans un brouillon juridique '
      'Firestore, sans modifier la version actuellement publiée. '
      'Vous pourrez ensuite les valider et les publier séparément.',
      'ENREGISTRER LE BROUILLON',
    );
    if (!confirmed || !mounted) return;

    setState(() { _saving = true; _message = null; });
    try {
      final created = await _editorRequest({
        'action': 'create', 'documentId': widget.documentId,
      });
      final draft = created['draft'];
      if (draft is! Map || draft['status'] != 'draft') {
        throw StateError('Le service n’a pas confirmé le brouillon.');
      }
      final stored = _articlesFromList(draft['chapters']);
      if (stored.length != expectedCount ||
          stored.length != data.articles.length) {
        throw StateError('Nombre d’articles enregistré différent du texte approuvé.');
      }
      for (var i = 0; i < stored.length; i++) {
        if (stored[i].id != data.articles[i].id ||
            stored[i].title != data.articles[i].title ||
            stored[i].content != data.articles[i].content) {
          throw StateError('Article ${stored[i].id} différent du texte approuvé.');
        }
      }
      // Relecture serveur indépendante : vérifie que le brouillon a
      // effectivement persisté dans Firebase après l'écriture.
      final reloaded = await _editorRequest({
        'action': 'status', 'documentId': widget.documentId,
      });
      final saved = reloaded['draft'];
      if (saved is! Map || saved['status'] != 'draft' ||
          _articlesFromList(saved['chapters']).length != expectedCount) {
        throw StateError('Enregistrement Firestore non confirmé.');
      }
      if (!mounted) return;
      setState(() {
        _future = _load();
        _selectedArticleId = null;
        _message = 'Brouillon enregistré dans Firebase : '
            '$expectedCount articles/rubriques. Non publié.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _message =
          'Enregistrement dans Firebase non confirmé : $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discardDraft(_LegalData data) async {
    final draft = data.editorDraft;
    if (draft == null ||
        (draft['status'] != 'draft' && draft['status'] != 'validated')) {
      return;
    }
    final confirmed = await _confirm(
      'ANNULER LA MODIFICATION ?',
      'Les modifications non publiées de ${widget.title} seront supprimées. '
      'Aucun document publié, aucune version juridique et aucune archive '
      'ne seront modifiés.',
      'ANNULER LA MODIFICATION',
    );
    if (!confirmed || !mounted) return;
    await _runEdit({
      'action': 'discard',
      'confirm': true,
      'expectedDraftRevision': draft['draftRevision'],
    }, 'Modification annulée. Version publiée et historique inchangés.');
  }

  Future<void> _save(_LegalData data) async {
    final draft = data.editorDraft;
    if (draft == null || _selectedArticleId == null ||
        _title.text.trim().isEmpty || _content.text.trim().isEmpty ||
        _changeSummary.text.trim().isEmpty) {
      setState(() => _message = 'Article et résumé des modifications requis.');
      return;
    }
    await _runEdit({
      'action': 'save',
      'expectedDraftRevision': draft['draftRevision'],
      'articleId': _selectedArticleId,
      'title': _title.text.trim(),
      'content': _content.text.trim(),
      'changeSummary': _changeSummary.text.trim(),
    }, 'Modification enregistrée. Elle n’est pas encore publiée.');
  }

  Future<void> _validate(_LegalData data) async {
    final draft = data.editorDraft;
    if (draft == null || draft['status'] != 'draft') return;
    final confirmed = await _confirm('VALIDER LA MODIFICATION ?',
      'Le contenu de ${widget.title} sera marqué comme validé. '
      'Cette étape ne le publie pas et n’affecte aucun utilisateur.',
      'VALIDER');
    if (!confirmed || !mounted) return;
    await _runEdit({'action': 'validate', 'confirm': true,
      'expectedDraftRevision': draft['draftRevision']},
      'Modification validée. Publication non effectuée.');
  }

  Future<void> _publish(_LegalData data) async {
    final draft = data.editorDraft;
    if (draft == null || draft['status'] != 'validated' ||
        !data.publicationEnabled || !data.initialPackPublished) {
      return;
    }
    final confirmed = await _confirm('PUBLIER UNE NOUVELLE VERSION ?',
      'Cette action remplacera officiellement le contenu de ${widget.title}, '
      'archivera la version antérieure et augmentera la version juridique '
      'globale. Les acceptations des utilisateurs devront être réévaluées. '
      'Aucune commande ni aucun paiement ne sera déclenché.',
      'PUBLIER ET ARCHIVER');
    if (!confirmed || !mounted) return;
    await _runEdit({'action': 'publish', 'confirm': true,
      'expectedDraftRevision': draft['draftRevision'],
      'expectedHash': draft['reviewedHash']},
      'Nouvelle version publiée et archivée. Vérifiez les acceptations.');
  }

  /// Importe les textes RGPD/PDC déjà revus dans le circuit sécurisé EXISTANT.
  /// Aucune écriture directe Firestore depuis Flutter : le serveur réalise
  /// successivement l'enregistrement, la validation, la publication et
  /// l'archivage de la version précédente.
  Future<void> _publishPreparedCommonArticles(_LegalData data) async {
    if (_saving || data.editorDraft != null ||
        !data.initialPackPublished || !data.publicationEnabled ||
        data.editorError != null ||
        (widget.documentId != 'rgpdNotice' &&
         widget.documentId != 'privacyPolicy')) {
      return;
    }

    try {
      final source = await rootBundle.loadString(
        'docs/publication_commune_preparee/'
        '${widget.documentId}_articles_prepares.json',
      );
      final raw = jsonDecode(source);
      if (raw is! Map) throw StateError('Corpus préparé invalide.');
      final prepared = Map<String, dynamic>.from(raw);
      final expectedCount = widget.documentId == 'rgpdNotice' ? 6 : 9;
      if (prepared['documentId'] != widget.documentId ||
          prepared['sourceVersion'] != data.version ||
          prepared['status'] != 'PREPARE_NON_PUBLIE') {
        throw StateError('Le document publié a changé : import interrompu.');
      }
      final original = _articlesFromList(prepared['sourceArticles']);
      final proposed = _articlesFromList(prepared['articles']);
      if (original.length != expectedCount ||
          proposed.length != expectedCount ||
          data.articles.length != expectedCount) {
        throw StateError('Nombre d’articles inattendu : import interrompu.');
      }
      for (var index = 0; index < expectedCount; index++) {
        final actual = data.articles[index];
        final before = original[index];
        final after = proposed[index];
        if (actual.id != before.id || actual.title != before.title.trim() ||
            actual.content != before.content.trim() ||
            after.id != before.id || after.title != before.title.trim() ||
            after.content.isEmpty) {
          throw StateError('Source publiée différente à l’article ${before.id}. '
              'Aucun import lancé.');
        }
      }
      final changes = <_LegalArticle>[];
      for (var index = 0; index < expectedCount; index++) {
        if (proposed[index].content != original[index].content) {
          changes.add(proposed[index]);
        }
      }
      if (changes.isEmpty) {
        if (mounted) setState(() => _message = 'Les articles sont déjà à jour.');
        return;
      }

      final confirmed = await _confirm(
        'PUBLIER ${widget.title} ?',
        '${changes.length} articles seront actualisés dans le document '
        'commun. Le service Super Admin enregistrera les changements, '
        'validera la modification, publiera la nouvelle version puis '
        'archivera la version précédente. Cette publication s’appliquera '
        'aux parcours Grand Public, Admin, Sauveteur et Publicitaire '
        'lors de leur prochain chargement.',
        'IMPORTER ET PUBLIER',
      );
      if (!confirmed || !mounted) return;

      setState(() { _saving = true; _message = null; });
      var savedCount = 0;
      try {
        final created = await _editorRequest({
          'action': 'create', 'documentId': widget.documentId,
        });
        final firstDraft = created['draft'];
        if (firstDraft is! Map || firstDraft['status'] != 'draft' ||
            firstDraft['draftRevision'] != 0) {
          throw StateError('Une modification existe déjà sur ce document. '
              'Elle doit être traitée séparément.');
        }
        var revision = 0;
        final changeSummary = widget.documentId == 'rgpdNotice'
            ? 'Actualisation RGPD : responsabilités des organismes, '
                'main courante, données de santé et droits des personnes.'
            : 'Actualisation de la confidentialité : finalités, '
                'main courante, données sensibles et conservation annuelle.';
        for (final article in changes) {
          final saved = await _editorRequest({
            'action': 'save',
            'documentId': widget.documentId,
            'expectedDraftRevision': revision,
            'articleId': article.id,
            'title': article.title,
            'content': article.content,
            'changeSummary': changeSummary,
          });
          final draft = saved['draft'];
          if (draft is! Map || draft['status'] != 'draft' ||
              draft['draftRevision'] != revision + 1) {
            throw StateError('Enregistrement non confirmé pour '
                'l’article ${article.id}.');
          }
          revision++;
          savedCount++;
        }
        final validated = await _editorRequest({
          'action': 'validate', 'documentId': widget.documentId,
          'confirm': true, 'expectedDraftRevision': revision,
        });
        final finalDraft = validated['draft'];
        final reviewedHash = finalDraft is Map
            ? _string(finalDraft['reviewedHash']) : '';
        if (finalDraft is! Map || finalDraft['status'] != 'validated' ||
            reviewedHash.isEmpty) {
          throw StateError('Validation serveur non confirmée.');
        }
        final published = await _editorRequest({
          'action': 'publish', 'documentId': widget.documentId,
          'confirm': true, 'expectedDraftRevision': revision,
          'expectedHash': reviewedHash,
        });
        if (published['published'] != true) {
          throw StateError('Publication non confirmée par le serveur.');
        }
        if (!mounted) return;
        setState(() {
          _selectedArticleId = null;
          _future = _load();
          _message = '${changes.length} articles publiés et version '
              'précédente archivée avec succès.';
        });
      } catch (error) {
        if (mounted) {
          setState(() {
            _future = _load();
            _message = 'Import interrompu après $savedCount enregistrement(s) : '
                '$error. La version publiée reste inchangée tant que '
                'la publication n’a pas été confirmée.';
          });
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Import impossible : $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LegalData>(
      future: _future,
      builder: (context, snapshot) {
        // Conserver le panneau deja affiche pendant le rafraichissement :
        // remplacer l'ExpansionTile par une jauge le refermait a chaque
        // creation, sauvegarde ou validation de brouillon.
        if (snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasData) {
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
            color: _blue.withValues(alpha: 0.035),
            border: Border.all(color: _blue.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ExpansionTile(
            key: ValueKey('legal-document-${widget.key}'),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(widget.title,
                style: const TextStyle(color: _blue, fontWeight: FontWeight.w800,
                    fontSize: 12)),
            subtitle: Text(data.editorDraft != null
                ? '${data.articles.length} articles · Modification '
                    '${data.editorDraft!['status'] == 'validated' ? 'validée' : 'en cours'}'
                : data.prepared
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
                  key: ValueKey('legal-article-${widget.key}-${article.id}'),
                  title: Text(article.title,
                      style: const TextStyle(color: _blue, fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  childrenPadding: const EdgeInsets.all(10),
                  children: [
                    SphotLegalArticleMarkdown(markdown: article.content),
                    Align(alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _saving || _editorEndpoint == null ||
                            data.editorError != null ||
                            !data.initialPackPublished
                            ? null : () => _startArticleEdit(data, article),
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
    final draftRevision = data.editorDraft?['draftRevision'];
    final hasSavedChanges = draftRevision is int && draftRevision > 0;
    final approvedImport = _initialProfessionalSections.containsKey(widget.documentId) &&
        data.editorDraft != null && data.prepared;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _red.withValues(alpha: 0.65)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('VERSION', style: TextStyle(color: _red,
              fontWeight: FontWeight.w900, fontSize: 14))),
          IconButton(
            tooltip: 'Actualiser le document et son historique',
            onPressed: _saving ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded, color: _blue, size: 20),
          ),
        ]),
        const SizedBox(height: 6),
        Text('Document : ${widget.title}',
            style: const TextStyle(color: _blue, fontSize: 12)),
        Text(!data.published
            ? 'Aucune version publiée · texte préparé pour Firebase'
            : 'Version publiée ${data.version} · Révision ${data.revision}',
            style: const TextStyle(color: _blue, fontSize: 12)),
        Text(data.prepared
            ? 'Texte définitif préparé — publication non effectuée'
            : 'Texte actuellement enregistré dans Firestore',
            style: const TextStyle(color: _red, fontSize: 11)),
        if (_initialProfessionalSections.containsKey(widget.documentId) &&
            data.prepared && data.editorDraft == null &&
            data.initialPackPublished && data.editorError == null) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : () => _registerApprovedDraft(data),
            icon: const Icon(Icons.save_outlined),
            label: const Text('ENREGISTRER DANS FIREBASE (BROUILLON)'),
          ),
        ],
        if ((widget.documentId == 'rgpdNotice' ||
             widget.documentId == 'privacyPolicy') &&
            data.initialPackPublished && data.publicationEnabled &&
            data.editorError == null && data.editorDraft == null) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : () =>
                _publishPreparedCommonArticles(data),
            icon: const Icon(Icons.system_update_alt_rounded),
            label: const Text('IMPORTER ET PUBLIER LES ARTICLES À JOUR'),
          ),
        ],
        if (data.editorDraft != null) ...[
          const SizedBox(height: 8),
          Text('Modification ${data.editorDraft!['status'] == 'validated' ? 'validée' : 'en cours'} '
              '· enregistrement n° ${data.editorDraft!['draftRevision']} '
              '· non publiée',
              style: const TextStyle(color: _blue, fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          const Text('Enregistrer conserve la modification ; valider la prépare. '
              'Seule la publication met à jour les textes accessibles dans SPHOT '
              'et archive la version précédente.',
              style: TextStyle(color: _blue, fontSize: 11)),
          if (_string(data.editorDraft!['changeSummary']).isNotEmpty)
            Text('Dernière modification : ${data.editorDraft!['changeSummary']}',
                style: const TextStyle(color: _blue, fontSize: 11)),
        ],
        if (data.updatedAt != null)
          Text('Dernière mise à jour : ${data.updatedAt!.day.toString().padLeft(2, '0')}/'
              '${data.updatedAt!.month.toString().padLeft(2, '0')}/'
              '${data.updatedAt!.year}',
              style: const TextStyle(color: _blue, fontSize: 11)),
        if (data.editorDraft != null && data.initialPackPublished &&
    (data.editorDraft!['status'] == 'draft' ||
     data.editorDraft!['status'] == 'validated')) ...[
  const SizedBox(height: 8),
  OutlinedButton.icon(
    onPressed: _saving ? null : () => _discardDraft(data),
    icon: const Icon(Icons.delete_outline, size: 16),
    label: const Text('ANNULER LA MODIFICATION',
      style: TextStyle(fontSize: 11)),
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFFB42318),
    ),
  ),
],
if (_selectedArticleId != null && data.editorDraft != null && data.initialPackPublished) ...[
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
              label: const Text('ENREGISTRER LA MODIFICATION')),
        ],
        if (_editorEndpoint == null)
          const Padding(padding: EdgeInsets.only(top: 8),
            child: Text('Circuit d’édition sécurisé préparé, mais service '
                'serveur non activé. Aucun texte publié ne peut être modifié.',
                style: TextStyle(color: _red, fontSize: 11))),
        if (data.editorError != null)
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Text('Éditeur indisponible : ${data.editorError}',
                style: const TextStyle(color: _red, fontSize: 11))),
        if (_editorEndpoint != null && data.editorError == null) ...[
          if (data.editorDraft != null)
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton.icon(
                onPressed: _saving || !data.initialPackPublished ||
                    !(hasSavedChanges || approvedImport) ||
                    data.editorDraft!['status'] != 'draft'
                    ? null : () => _validate(data),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('VALIDER LA MODIFICATION'),
              ),
              FilledButton.icon(
                onPressed: _saving || !data.publicationEnabled ||
                    !data.initialPackPublished ||
                    data.editorDraft!['status'] != 'validated'
                    ? null : () => _publish(data),
                icon: const Icon(Icons.publish_outlined),
                label: const Text('PUBLIER ET ARCHIVER'),
              ),
            ]),
          if (!data.initialPackPublished)
            const Padding(padding: EdgeInsets.only(top: 6),
              child: Text('Modification individuelle disponible après la '
                  'publication initiale des cinq textes validés.',
                  style: TextStyle(color: _red, fontSize: 11))),
          if (data.editorDraft != null && !data.publicationEnabled)
            const Padding(padding: EdgeInsets.only(top: 6),
              child: Text('Publication non activée côté serveur. '
                  'L’enregistrement et la validation restent distincts.',
                  style: TextStyle(color: _red, fontSize: 11))),
        ],
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
