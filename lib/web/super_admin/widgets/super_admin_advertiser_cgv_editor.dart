import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../advertiser/widgets/advertiser_cgv_policy.dart';

/// CGV propres au parcours publicitaire : versionnement indépendant des CGU.
class SuperAdminAdvertiserCgvEditor extends StatefulWidget {
  const SuperAdminAdvertiserCgvEditor({super.key});

  @override
  State<SuperAdminAdvertiserCgvEditor> createState() =>
      _SuperAdminAdvertiserCgvEditorState();
}

class _SuperAdminAdvertiserCgvEditorState
    extends State<SuperAdminAdvertiserCgvEditor> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _published = false;
  String _version = AdvertiserCgvPolicy.defaultVersion;
  String? _error;

  DocumentReference<Map<String, dynamic>> get _reference =>
      FirebaseFirestore.instance.collection('legalDocuments')
          .doc(AdvertiserCgvPolicy.documentId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await _reference.get();
      final data = snap.data() ?? AdvertiserCgvPolicy.initialDocument;
      final chapters = (data['chapters'] as List?) ?? const [];
      String value = AdvertiserCgvPolicy.radiusArticle;
      for (final item in chapters) {
        if (item is Map &&
            item['title'] == AdvertiserCgvPolicy.radiusArticleTitle) {
          value = (item['content'] ?? value).toString();
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _controller.text = value;
        _version = (data['version'] ??
            AdvertiserCgvPolicy.defaultVersion).toString();
        _published = snap.exists && data['published'] == true;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de lire les CGV publicitaires : $e';
      });
    }
  }

  Future<void> _publish() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(_reference);
        final old = snap.data() ?? AdvertiserCgvPolicy.initialDocument;
        final previous = (old['chapters'] as List?) ?? const [];
        final chapters = <Map<String, dynamic>>[
          for (final item in previous)
            if (item is Map) Map<String, dynamic>.from(item),
        ];
        final index = chapters.indexWhere((chapter) =>
            chapter['title'] == AdvertiserCgvPolicy.radiusArticleTitle);
        final previousContent = index < 0 ? '' :
            (chapters[index]['content'] ?? '').toString();
        if (index < 0) {
          chapters.add({
            'title': AdvertiserCgvPolicy.radiusArticleTitle,
            'content': content,
          });
        } else {
          chapters[index]['content'] = content;
        }
        final alreadyPublished = snap.exists && old['published'] == true;
        if (alreadyPublished && previousContent == content) return;
        final revision = old['revision'] is int
            ? old['revision'] as int : 0;
        final nextRevision = alreadyPublished ? revision + 1 : 0;
        final version = '1.$nextRevision';
        final history = [
          if (old['history'] is List) ...(old['history'] as List),
          if (alreadyPublished) {
            'version': old['version'],
            'chapters': previous,
            'archivedAt': Timestamp.now(),
          },
        ];
        tx.set(_reference, {
          'title': AdvertiserCgvPolicy.title,
          'audience': 'advertiser',
          'published': true,
          'version': version,
          'revision': nextRevision,
          'chapters': chapters,
          'history': history,
          'publishedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Publication CGV impossible : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E3A8A)),
      ),
      child: ExpansionTile(
        title: const Text('CGV — SPHOT PUBLICITAIRE',
          style: TextStyle(fontWeight: FontWeight.w900,
              color: Color(0xFF1E3A8A))),
        subtitle: Text(_published
            ? 'Version publiée : $_version'
            : 'Article initial à publier sur Firestore'),
        childrenPadding: const EdgeInsets.all(14),
        children: [
          if (_loading) const CircularProgressIndicator()
          else ...[
            const Text(AdvertiserCgvPolicy.radiusArticleTitle,
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 13,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Article CGV — rayon de diffusion',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Chaque modification publiée crée une nouvelle version '
              'et conserve le texte précédent dans l’historique du '
              'document. Cette édition ne change pas les CGU communes.',
              style: TextStyle(fontSize: 12),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _saving ? null : _publish,
              child: Text(_saving ? 'PUBLICATION EN COURS…'
                  : 'ENREGISTRER ET VERSIONNER LES CGV'),
            ),
          ],
        ],
      ),
    );
  }
}
