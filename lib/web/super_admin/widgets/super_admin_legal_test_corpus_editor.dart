import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../pages/sauveteur/widgets/sauveteur_styled_dropdown.dart';
import 'sphot_legal_markdown_preview.dart';

/// Corpus consolidé de novembre 2026, uniquement pour le projet C4 TEST.
/// Les documents restent non publiés et ne servent jamais de preuve de CGV
/// acceptées, de commande, de facture ou de paiement.
class SuperAdminLegalTestCorpusEditor extends StatefulWidget {
  const SuperAdminLegalTestCorpusEditor({super.key});

  static const testProjectId = 'sphot-c4-test-20261029';
  static const testFlag = bool.fromEnvironment(
    'SPHOT_LEGAL_TEST_MODE', defaultValue: false);
  static const previewOnly = bool.fromEnvironment(
    'SPHOT_LEGAL_C4_PREVIEW_ONLY', defaultValue: false);

  @override
  State<SuperAdminLegalTestCorpusEditor> createState() =>
      _SuperAdminLegalTestCorpusEditorState();
}

class _CorpusDocument {
  const _CorpusDocument(this.id, this.label, this.asset, this.audience);

  final String id;
  final String label;
  final String asset;
  final String audience;
}

class _CorpusArticle {
  const _CorpusArticle(this.title, this.content);

  final String title;
  final String content;
}

class _SuperAdminLegalTestCorpusEditorState
    extends State<SuperAdminLegalTestCorpusEditor> {
  static const _documents = <_CorpusDocument>[
    _CorpusDocument('adminCgv', 'CGV — SPHOT ADMIN',
        'assets/legal/test_corpus/cgv_admin.md', 'admin'),
    _CorpusDocument('advertiserCgv', 'CGV — SPHOT PUBLICITAIRE',
        'assets/legal/test_corpus/cgv_publicitaire.md', 'advertiser'),
    _CorpusDocument('publicCgu', 'CGU — GRAND PUBLIC',
        'assets/legal/test_corpus/cgu_grand_public.md', 'public'),
    _CorpusDocument('sauveteurCgu', 'CGU — SPHOT SAUVETEUR',
        'assets/legal/test_corpus/cgu_sauveteur.md', 'sauveteur'),
    _CorpusDocument('sauveteurCharter', 'CHARTE — SPHOT SAUVETEUR',
        'assets/legal/test_corpus/charte_sauveteur.md', 'sauveteur'),
  ];

  final _title = TextEditingController();
  final _content = TextEditingController();
  int _documentIndex = 0;
  int _articleIndex = 0;
  List<_CorpusArticle> _articles = const [];
  bool _loading = true;
  bool _saving = false;
  bool _stored = false;
  int _loadToken = 0;
  String _version = 'BROUILLON LOCAL';
  String? _message;

  bool get _enabled => SuperAdminLegalTestCorpusEditor.testFlag &&
      Firebase.app().options.projectId ==
          SuperAdminLegalTestCorpusEditor.testProjectId;

  _CorpusDocument get _selected => _documents[_documentIndex];

  DocumentReference<Map<String, dynamic>> get _reference =>
      FirebaseFirestore.instance.collection('legalTestCorpus').doc(_selected.id);

  @override
  void initState() {
    super.initState();
    if (_enabled) {
      _load();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  static List<_CorpusArticle> _parseMarkdown(String source) {
    final articles = <_CorpusArticle>[];
    String? heading;
    final paragraphs = <String>[];

    void finish() {
      if (heading != null) {
        articles.add(_CorpusArticle(heading, paragraphs.join('\n').trim()));
      }
      paragraphs.clear();
    }

    for (final line in source.split('\n')) {
      if (line.startsWith('## ')) {
        finish();
        heading = line.substring(3).trim();
      } else if (heading != null) {
        paragraphs.add(line);
      }
    }
    finish();
    return articles;
  }

  void _showArticle(int index) {
    if (index < 0 || index >= _articles.length) return;
    _articleIndex = index;
    _title.text = _articles[index].title;
    _content.text = _articles[index].content;
  }

  Future<void> _load() async {
    if (!_enabled) return;
    final token = ++_loadToken;
    final document = _selected;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final source = await rootBundle.loadString(document.asset);
      final initial = _parseMarkdown(source);
      if (initial.isEmpty) throw StateError('Corpus sans articles.');
      if (SuperAdminLegalTestCorpusEditor.previewOnly) {
        if (!mounted || token != _loadToken) return;
        setState(() {
          _articles = initial;
          _stored = false;
          _version = 'APERÇU LOCAL — SANS ÉCRITURE';
          _loading = false;
          _showArticle(0);
        });
        return;
      }
      final reference = FirebaseFirestore.instance.collection('legalTestCorpus')
          .doc(document.id);
      final snapshot = await reference.get();
      final data = snapshot.data();
      if (data != null &&
          (data['testOnly'] != true || data['published'] == true)) {
        throw StateError('Document déjà utilisé hors du corpus TEST : '
            'modification refusée.');
      }
      final remote = data?['chapters'];
      final articles = remote is List
          ? remote.whereType<Map>().map((entry) => _CorpusArticle(
              (entry['title'] ?? '').toString(),
              (entry['content'] ?? '').toString())).toList()
          : initial;
      if (articles.isEmpty) throw StateError('Document sans article.');
      if (!mounted || token != _loadToken) return;
      setState(() {
        _articles = articles;
        _stored = snapshot.exists;
        _version = (data?['version'] ?? 'BROUILLON LOCAL').toString();
        _loading = false;
        _showArticle(0);
      });
    } catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _stored = false;
        _articles = const [];
        _message = 'Lecture du corpus TEST impossible : $error';
      });
    }
  }

  Future<void> _createTestDraft() async {
    if (!_enabled || _saving || _stored || _articles.isEmpty) return;
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Authentification obligatoire.');
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final existing = await tx.get(_reference);
        if (existing.exists) {
          throw StateError('Document existant : aucun écrasement autorisé.');
        }
        tx.set(_reference, {
          'title': _selected.label,
          'audience': _selected.audience,
          'testOnly': true,
          'published': false,
          'version': '1.0',
          'revision': 1,
          'chapters': [
            for (final article in _articles)
              {'title': article.title, 'content': article.content},
          ],
          'createdByUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _message = 'Import TEST refusé : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveTestArticle() async {
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (!_enabled || !_stored || _saving || title.isEmpty || content.isEmpty) {
      return;
    }
    final original = _articles[_articleIndex];
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Authentification obligatoire.');
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snapshot = await tx.get(_reference);
        final data = snapshot.data();
        if (data == null || data['testOnly'] != true ||
            data['published'] == true || data['chapters'] is! List) {
          throw StateError('Modification hors brouillon C4 TEST interdite.');
        }
        final chapters = [
          for (final entry in data['chapters'] as List)
            Map<String, dynamic>.from(entry as Map),
        ];
        if (_articleIndex >= chapters.length) {
          throw StateError('Article modifié par une autre session.');
        }
        final previous = chapters[_articleIndex];
        if (previous['title'] != original.title ||
            previous['content'] != original.content) {
          throw StateError('Article modifié par une autre session : '
              'rechargement requis.');
        }
        if (previous['title'] == title && previous['content'] == content) {
          return;
        }
        final revision = data['revision'] is int
            ? data['revision'] as int : 0;
        final historyRef = _reference.collection('versions')
            .doc('test_${revision.toString().padLeft(6, '0')}');
        tx.set(historyRef, {
          'testOnly': true,
          'version': data['version'],
          'chapters': data['chapters'],
          'archivedAt': FieldValue.serverTimestamp(),
          'replacedByUid': uid,
        });
        chapters[_articleIndex] = {'title': title, 'content': content};
        tx.update(_reference, {
          'chapters': chapters,
          'revision': revision + 1,
          'version': '1.0',
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByUid': uid,
        });
      });
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _message = 'Enregistrement TEST refusé : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Enregistre les cinq textes consolidés dans les brouillons C4 existants.
  /// Les publications réelles (legalDocuments) ne sont jamais modifiées.
  Future<void> _integrateConsolidatedCorpus() async {
    if (!_enabled || SuperAdminLegalTestCorpusEditor.previewOnly ||
        _saving || _loading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('INTÉGRER LES 5 TEXTES CONSOLIDÉS ?'),
        content: const Text('Les cinq textes seront enregistrés comme '
            'brouillons SPHOT version 1.0. Les anciennes rédactions '
            'de travail pourront être remplacées, sans publication, '
            'sans commande et sans paiement. Les documents publiés '
            'dans legalDocuments resteront inchangés.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ANNULER'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('INTÉGRER LES 5 BROUILLONS'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _saving = true; _message = null; });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Authentification obligatoire.');

      // Tous les fichiers doivent être disponibles avant toute écriture.
      final corpus = <String, List<Map<String, String>>>{};
      for (final document in _documents) {
        final markdown = await rootBundle.loadString(document.asset);
        final articles = _parseMarkdown(markdown);
        if (articles.isEmpty || articles.any((article) =>
            article.title.isEmpty || article.content.isEmpty)) {
          throw StateError('Article manquant dans ${document.label}.');
        }
        corpus[document.id] = [
          for (final article in articles)
            {'title': article.title, 'content': article.content},
        ];
      }

      var changed = 0;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final refs = <String, DocumentReference<Map<String, dynamic>>>{};
        final snapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final document in _documents) {
          final ref = FirebaseFirestore.instance.collection('legalTestCorpus')
              .doc(document.id);
          refs[document.id] = ref;
          snapshots[document.id] = await transaction.get(ref);
        }

        var count = 0;
        for (final document in _documents) {
          final snapshot = snapshots[document.id]!;
          final previous = snapshot.data();
          if (previous != null &&
              (previous['testOnly'] != true || previous['published'] == true)) {
            throw StateError('Document hors brouillon C4 : ${document.label}.');
          }
          final articles = corpus[document.id]!;
          final sameContent = previous != null &&
              jsonEncode(previous['chapters']) == jsonEncode(articles);
          if (sameContent && previous?['version'] == '1.0') continue;

          final previousRevision = previous?['revision'] is int
              ? previous!['revision'] as int : 0;
          final record = <String, dynamic>{
            'title': document.label,
            'audience': document.audience,
            'testOnly': true,
            'published': false,
            'version': '1.0',
            'revision': previousRevision + 1,
            'chapters': articles,
            'createdByUid': previous?['createdByUid'] ?? uid,
            'createdAt': previous?['createdAt'] ??
                FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedByUid': uid,
          };
          if (snapshot.exists) {
            transaction.update(refs[document.id]!, record);
          } else {
            transaction.set(refs[document.id]!, record);
          }
          count++;
        }
        changed = count;
      });
      if (!mounted) return;
      await _load();
      if (mounted) setState(() => _message =
          '$changed document(s) actualisé(s) en version 1.0. '
          'Les cinq brouillons restent modifiables et non publiés.');
    } catch (error) {
      if (mounted) setState(() =>
          _message = 'Intégration des textes impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        border: Border.all(color: const Color(0xFFC27B15)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ExpansionTile(
        initiallyExpanded: SuperAdminLegalTestCorpusEditor.previewOnly,
        title: const Text('DOCUMENTS PAR PROFIL · C4 TEST',
            style: TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('Brouillons non publiés · $_version'),
        childrenPadding: const EdgeInsets.all(14),
        children: [
          const Text('TEST uniquement. Aucun document ici ne peut être '
              'utilisé pour accepter des CGV, commander ou payer.',
              style: TextStyle(fontSize: 12)),
          if (!SuperAdminLegalTestCorpusEditor.previewOnly) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || _loading ? null :
                    _integrateConsolidatedCorpus,
                icon: const Icon(Icons.library_add_check_outlined),
                label: const Text('INTÉGRER LES 5 TEXTES CONSOLIDÉS'),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Cette intégration remplace uniquement les anciens '
                'brouillons C4. Les versions publiées restent intactes.',
                style: TextStyle(fontSize: 11)),
          ],
          if (SuperAdminLegalTestCorpusEditor.previewOnly)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('APERÇU LOCAL : aucune lecture ni écriture Firestore. '
                  'Les modifications saisies ne sont pas enregistrées. '
                  'Le versionnement sera vérifié séparément.',
                  style: TextStyle(color: Color(0xFF9B1C1C))),
            ),
          const SizedBox(height: 10),
          SauveteurStyledDropdown(
            labelText: 'Profil et document',
            value: _documentIndex.toString(),
            enabled: !_saving,
            maxMenuHeight: 280,
            options: [
              for (var index = 0; index < _documents.length; index++)
                SauveteurDropdownOption(
                    value: index.toString(), label: _documents[index].label),
            ],
            onChanged: (value) {
              final index = int.tryParse(value);
              if (index == null || index == _documentIndex) return;
              setState(() => _documentIndex = index);
              _load();
            },
          ),
          if (_loading) const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator())
          else if (_articles.isNotEmpty) ...[
            const SizedBox(height: 12),
            SauveteurStyledDropdown(
              labelText: 'Article',
              value: _articleIndex.toString(),
              enabled: !_saving,
              maxMenuHeight: 320,
              options: [
                for (var index = 0; index < _articles.length; index++)
                  SauveteurDropdownOption(
                      value: index.toString(), label: _articles[index].title),
              ],
              onChanged: (value) {
                final index = int.tryParse(value);
                if (index == null || index == _articleIndex) return;
                setState(() => _showArticle(index));
              },
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF1E3A8A), width: 1.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _title,
                    builder: (context, current, child) => Text(
                      current.text,
                      style: const TextStyle(
                        color: Color(0xFF1E3A8A),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Divider(height: 24),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _content,
                    builder: (context, current, child) =>
                        SphotLegalMarkdownPreview(source: current.text),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('MODIFIER L’ARTICLE — TEXTE SOURCE',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              children: [
                TextField(controller: _title,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(), labelText: 'Titre')),
                const SizedBox(height: 10),
                TextField(controller: _content, minLines: 8, maxLines: 16,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Contenu intégral de l’article')),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: SuperAdminLegalTestCorpusEditor.previewOnly
                  ? null : _saving ? null :
                  (_stored ? _saveTestArticle : _createTestDraft),
              icon: const Icon(Icons.save_outlined),
              label: Text(SuperAdminLegalTestCorpusEditor.previewOnly
                  ? 'ENREGISTREMENT DÉSACTIVÉ — APERÇU'
                  : _saving ? 'ENREGISTREMENT…' : _stored
                  ? 'ENREGISTRER LA MODIFICATION DU BROUILLON'
                  : 'ENREGISTRER CE BROUILLON 1.0'),
            ),
          ],
          if (_message != null) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_message!,
                style: const TextStyle(color: Color(0xFF9B1C1C))),
          ),
        ],
      ),
    );
  }
}
