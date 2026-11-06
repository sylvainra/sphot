import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../pages/sauveteur/widgets/sauveteur_styled_dropdown.dart';

/// Édition des documents propres aux profils SPHOT dans la même collection
/// que celle consultée par les parcours. Aucune commande ni acceptation ici.
class SuperAdminProfileLegalEditor extends StatefulWidget {
  const SuperAdminProfileLegalEditor({super.key});

  @override
  State<SuperAdminProfileLegalEditor> createState() =>
      _SuperAdminProfileLegalEditorState();
}

class _SuperAdminProfileLegalEditorState
    extends State<SuperAdminProfileLegalEditor> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);
  static const _documents = <String, String>{
    'adminCgv': 'CGV — SPHOT ADMIN',
    'advertiserCgv': 'CGV — SPHOT PUBLICITAIRE',
    'sauveteurCgu': 'CGU — SPHOT SAUVETEUR',
    'sauveteurCharter': 'CHARTE — SPHOT SAUVETEUR',
  };
  static const _consolidatedSources = <String, String>{
    'adminCgv': 'assets/legal/test_corpus/cgv_admin.md',
    'advertiserCgv': 'assets/legal/test_corpus/cgv_publicitaire.md',
    'sauveteurCgu': 'assets/legal/test_corpus/cgu_sauveteur.md',
    'sauveteurCharter': 'assets/legal/test_corpus/charte_sauveteur.md',
  };

  final _chapterTitle = TextEditingController();
  final _chapterContent = TextEditingController();
  String _documentId = 'adminCgv';
  String? _chapterId;
  List<Map<String, dynamic>> _chapters = [];
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void dispose() {
    _chapterTitle.dispose();
    _chapterContent.dispose();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    final requested = _documentId;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ref = FirebaseFirestore.instance
          .collection('legalDocuments').doc(requested);
      final document = await ref.get();
      final chapters = await ref.collection('chapters')
          .orderBy(FieldPath.documentId).get();
      final parent = document.data() ?? <String, dynamic>{};
      // La CGV Publicitaire est historiquement lue dans le document parent.
      // Le Super Admin doit éditer exactement cette même représentation.
      final items = requested != 'advertiserCgv' && chapters.docs.isNotEmpty
          ? chapters.docs.map((chapter) => <String, dynamic>{
              'id': chapter.id,
              ...chapter.data(),
            }).toList()
          : ((parent['chapters'] is List)
              ? (parent['chapters'] as List).asMap().entries.map((entry) {
                  final value = entry.value;
                  final data = value is Map
                      ? Map<String, dynamic>.from(value)
                      : <String, dynamic>{};
                  return <String, dynamic>{
                    'id': (entry.key + 1).toString().padLeft(2, '0'),
                    ...data,
                  };
                }).toList()
              : <Map<String, dynamic>>[]);
      if (!mounted || requested != _documentId) return;
      setState(() {
        _chapters = items;
        _busy = false;
      });
      _selectChapter(items.isEmpty ? null : items.first['id'].toString());
    } catch (error) {
      if (!mounted || requested != _documentId) return;
      setState(() {
        _busy = false;
        _message = 'Lecture impossible : $error';
      });
    }
  }

  void _selectChapter(String? chapterId) {
    final matching = _chapters.where((item) => item['id'] == chapterId);
    final chapter = matching.isEmpty ? <String, dynamic>{} : matching.first;
    setState(() {
      _chapterId = chapterId;
      _chapterTitle.text = (chapter['title'] ?? chapter['titre'] ?? '')
          .toString();
      _chapterContent.text = (chapter['content'] ?? chapter['texte'] ?? '')
          .toString();
      _message = null;
    });
  }

  void _newChapter() {
    final ids = _chapters
        .map((chapter) => int.tryParse(chapter['id'].toString()) ?? 0);
    final next = ids.fold<int>(0, (maximum, id) => id > maximum ? id : maximum) + 1;
    _selectChapter(next.toString().padLeft(2, '0'));
  }

  Future<void> _saveChapter() async {
    final title = _chapterTitle.text.trim();
    final content = _chapterContent.text.trim();
    final chapterId = _chapterId;
    if (chapterId == null || title.isEmpty || content.isEmpty || _busy) {
      setState(() => _message = 'Titre et contenu obligatoires.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ref = FirebaseFirestore.instance
          .collection('legalDocuments').doc(_documentId);
      final payload = <String, dynamic>{
        'title': title,
        'content': content,
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_documentId == 'advertiserCgv') {
        // L'annonceur consulte les articles intégrés au document parent.
        final updated = _chapters.map((chapter) => Map<String, dynamic>.from(chapter))
            .toList();
        final existing = updated.indexWhere((chapter) => chapter['id'] == chapterId);
        final item = <String, dynamic>{'id': chapterId, 'title': title,
          'content': content};
        if (existing < 0) {
          updated.add(item);
        } else {
          updated[existing] = item;
        }
        await ref.set({
          'title': _documents[_documentId],
          'version': '1.0',
          'revision': FieldValue.increment(1),
          'chapters': updated,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        final batch = FirebaseFirestore.instance.batch();
        batch.set(ref, {
          'title': _documents[_documentId],
          'version': '1.0',
          'revision': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        batch.set(ref.collection('chapters').doc(chapterId), {
          ...payload,
          'order': int.tryParse(chapterId) ?? 1,
        }, SetOptions(merge: true));
        await batch.commit();
      }
      if (!mounted) return;
      await _loadDocument();
      if (!mounted) return;
      setState(() => _message = 'Article enregistré dans Firestore — Version 1.0.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Enregistrement impossible : $error';
      });
    }
  }

  Future<void> _confirmSaveActiveChapter() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('MODIFIER UN DOCUMENT ACTIF ?'),
        content: const Text('Cette commande modifie les articles actuellement '
            'enregistrés dans legalDocuments, qui peuvent être consultés par '
            'les utilisateurs. Pour intégrer les cinq textes consolidés sans '
            'publication, utilisez l’éditeur du corpus C4. '
            'Voulez-vous réellement modifier le document actif ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ANNULER'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('MODIFIER LE DOCUMENT ACTIF'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _saveChapter();
  }

  /// Affiche les brouillons locaux sans lecture ni écriture Firestore.
  /// Le dossier test_corpus n'est jamais une source de publication réelle.
  Future<void> _previewConsolidatedDocuments({String? onlyDocumentId}) async {
    if (_busy) return;
    final sources = _consolidatedSources.entries.where((entry) =>
        onlyDocumentId == null || entry.key == onlyDocumentId).toList();
    if (sources.isEmpty) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final documentPanels = <Widget>[];
      for (final entry in sources) {
        final raw = await rootBundle.loadString(entry.value);
        final headings = RegExp(r'^##\s+(.+)$', multiLine: true)
            .allMatches(raw).toList();
        if (headings.isEmpty) {
          throw StateError('Aucun article dans ${entry.key}.');
        }
        final articles = <Widget>[];
        for (var index = 0; index < headings.length; index++) {
          final heading = headings[index];
          final end = index + 1 < headings.length
              ? headings[index + 1].start : raw.length;
          final title = (heading.group(1) ?? '').trim();
          final content = raw.substring(heading.end, end).trim();
          if (title.isEmpty || content.isEmpty) {
            throw StateError('Article incomplet dans ${entry.key}.');
          }
          articles.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: _blue,
                    fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                SelectableText(content),
                const Divider(height: 18),
              ],
            ),
          ));
        }
        documentPanels.add(ExpansionTile(
          initiallyExpanded: sources.length == 1,
          title: Text(_documents[entry.key] ?? entry.key,
              style: const TextStyle(color: _blue,
                  fontWeight: FontWeight.w800)),
          subtitle: Text('${articles.length} articles — brouillon non publié'),
          children: articles,
        ));
      }

      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('PRÉVISUALISATION DES TEXTES — C4 TEST',
                    style: TextStyle(color: _blue, fontSize: 17,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('Lecture seule : aucune publication, acceptation, '
                    'commande ou modification Firestore.',
                    style: TextStyle(color: _red, fontSize: 12)),
                const SizedBox(height: 12),
                Flexible(child: ListView(shrinkWrap: true,
                    children: documentPanels)),
                Align(alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('FERMER'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Prévisualisation indisponible : $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _blue.withOpacity(0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue, width: 1.4),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: _red,
        collapsedIconColor: _red,
        title: const Text('DOCUMENTS PAR PROFIL',
            style: TextStyle(color: _blue, fontSize: 14,
                fontWeight: FontWeight.w900)),
        subtitle: const Text('Documents communs aux parcours professionnels',
            style: TextStyle(color: _blue, fontSize: 11)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _previewConsolidatedDocuments,
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue, foregroundColor: Colors.white),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('PRÉVISUALISER LES 4 TEXTES — TEST'),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Ces textes C4 sont des brouillons non publiés. '
              'Une publication réelle exigera une validation et un '
              'historique des versions distincts.',
              style: TextStyle(color: _red, fontSize: 11)),
          const SizedBox(height: 5),
          const Text('Les CGU Grand Public sont intégrées depuis '
              'l’éditeur du corpus C4, avec les quatre textes professionnels.',
              style: TextStyle(color: _blue, fontSize: 11)),
          const SizedBox(height: 12),
          SauveteurStyledDropdown(
            labelText: 'Profil et document',
            value: _documentId,
            enabled: !_busy,
            maxMenuHeight: 280,
            options: _documents.entries.map((entry) => SauveteurDropdownOption(
              value: entry.key,
              label: entry.value,
            )).toList(),
            onChanged: (value) {
              setState(() => _documentId = value);
              _loadDocument();
            },
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(color: _blue),
          if (_chapters.isEmpty && !_busy)
            const Text('Aucun article enregistré pour ce document.',
                style: TextStyle(color: _blue, fontSize: 12)),
          if (_chapters.isNotEmpty) SauveteurStyledDropdown(
            labelText: 'Article',
            value: _chapterId,
            enabled: !_busy,
            maxMenuHeight: 320,
            options: _chapters.map((chapter) => SauveteurDropdownOption(
              value: chapter['id'].toString(),
              label: (chapter['title'] ?? '').toString(),
            )).toList(),
            onChanged: _selectChapter,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy ? null : _newChapter,
              icon: const Icon(Icons.add, color: _blue),
              label: const Text('AJOUTER UN ARTICLE',
                  style: TextStyle(color: _blue)),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () =>
                  _previewConsolidatedDocuments(onlyDocumentId: _documentId),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('PRÉVISUALISER CE TEXTE — TEST'),
            ),
          ),
          const SizedBox(height: 8),
          if (_chapterId != null) ...[
            TextField(
              controller: _chapterTitle,
              decoration: const InputDecoration(
                labelText: 'Titre de l’article', border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _chapterContent,
              minLines: 7,
              maxLines: 16,
              decoration: const InputDecoration(
                labelText: 'Texte de l’article', border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _confirmSaveActiveChapter,
                style: ElevatedButton.styleFrom(backgroundColor: _blue,
                    foregroundColor: Colors.white),
                icon: const Icon(Icons.save_rounded),
                label: const Text('ENREGISTRER L’ARTICLE ACTIF'),
              ),
            ),
          ],
          if (_message != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!,
                style: const TextStyle(color: _blue, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
