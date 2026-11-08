import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Premier lot juridique : cinq documents, 54 articles.
/// Une validation ne publie jamais ; la publication est une action distincte.
class SuperAdminInitialLegalPackPanel extends StatefulWidget {
  const SuperAdminInitialLegalPackPanel({super.key});

  @override
  State<SuperAdminInitialLegalPackPanel> createState() =>
      _SuperAdminInitialLegalPackPanelState();
}

class _SuperAdminInitialLegalPackPanelState
    extends State<SuperAdminInitialLegalPackPanel> {
  static const _blue = Color(0xFF213F8E);
  static const _red = Color(0xFFE52525);
  static const _editorUrl = String.fromEnvironment(
    'SPHOT_LEGAL_DOCUMENT_EDITOR_URL', defaultValue: '');

  Map<String, dynamic>? _status;
  String? _error;
  String? _message;
  bool _loading = false;
  bool _busy = false;

  Uri? get _endpoint {
    final uri = Uri.tryParse(_editorUrl.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.host != 'us-central1-sphot-ab80b.cloudfunctions.net' ||
        uri.path != '/manageSphotLegalDocumentEditing') {
      return null;
    }
    return uri.replace(path: '/manageSphotInitialLegalPack');
  }

  List<Map<String, dynamic>> get _documents {
    final source = _status?['documents'];
    if (source is! List) return const [];
    return source.whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row)).toList();
  }

  bool get _canValidate => !_loading && !_busy &&
      _status?['validationEnabled'] == true &&
      _documents.length == 5 &&
      _documents.any((row) => row['status'] == 'draft') &&
      _documents.every((row) =>
          row['status'] == 'draft' || row['status'] == 'validated');

  bool get _canPublish {
    if (_loading || _busy || _status?['publicationEnabled'] != true ||
        _status?['ready'] != true || _documents.length != 5) {
      return false;
    }
    final hash = _status?['packHash']?.toString() ?? '';
    final version = _status?['currentVersion']?.toString() ?? '';
    return RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) &&
        RegExp(r'^\d{1,3}\.\d{1,4}$').hasMatch(version);
  }

  @override
  void initState() {
    super.initState();
    if (_endpoint != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> body) async {
    final endpoint = _endpoint;
    if (endpoint == null) throw StateError('Service non configuré.');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Connexion Super Admin requise.');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('Session Firebase indisponible.');
    }
    final response = await http.post(endpoint, headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    }, body: jsonEncode(body)).timeout(const Duration(seconds: 45));

    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Une réponse non JSON est traitée comme une erreur serveur.
    }
    if (response.statusCode != 200 || data?['success'] != true) {
      throw StateError('Service juridique : '
          '${data?['error'] ?? response.statusCode}');
    }
    return data!;
  }

  Future<void> _load() async {
    if (_loading || _busy) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _request({'action': 'status'});
      if (mounted) setState(() => _status = result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = null;
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit({required bool publish}) async {
    if (publish ? !_canPublish : !_canValidate) return;
    final state = _status!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(publish ? 'PUBLIER LE LOT INITIAL ?' :
            'VALIDER LES CINQ DOCUMENTS ?'),
        content: Text(publish
            ? 'Cette action publiera officiellement les 54 articles des cinq '
                'documents, archivera les versions antérieures et augmentera '
                'la version juridique. Elle est distincte de la validation.'
            : 'Les cinq brouillons seront validés ensemble. '
                'Aucun document ne sera publié à cette étape.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ANNULER')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(publish ? 'PUBLIER ET ARCHIVER' : 'VALIDER LE LOT'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    bool succeeded = false;
    try {
      await _request(publish
          ? {
              'action': 'publish',
              'confirm': true,
              'expectedPackHash': state['packHash'],
              'expectedVersion': state['currentVersion'],
            }
          : {'action': 'validate'});
      succeeded = true;
      if (mounted) {
        setState(() => _message = publish
            ? 'Lot initial publié et archivé.'
            : 'Cinq brouillons validés, sans publication.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (succeeded && mounted) await _load();
  }

  String _statusLabel(Object? raw) {
    const names = <String, String>{
      'draft': 'Brouillon',
      'validated': 'Validé',
      'published': 'Publié',
      'absent': 'Absent',
    };
    final key = raw?.toString() ?? 'absent';
    return names[key] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final docs = _documents;
    final version = _status?['currentVersion']?.toString() ?? '—';
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.055),
        border: Border.all(color: _blue, width: 1.5),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('LOT INITIAL — 5 DOCUMENTS / 54 ARTICLES',
            style: TextStyle(color: _blue, fontWeight: FontWeight.w900,
                fontSize: 13)),
        const SizedBox(height: 6),
        const Text('Validation globale et publication officielle séparées. '
            'Aucune publication lors de l’enregistrement ou de la validation.',
            style: TextStyle(fontSize: 11, height: 1.4)),
        const SizedBox(height: 9),
        if (_endpoint == null)
          const Text('Service sécurisé non configuré sur ce portail. '
              'Aucune action disponible.',
              style: TextStyle(color: _red, fontSize: 11)),
        if (_loading) const LinearProgressIndicator(),
        if (_status != null) ...[
          Text('Version juridique actuelle : $version',
              style: const TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final doc in docs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text(doc['label']?.toString() ??
                    doc['id']?.toString() ?? 'Document',
                    style: const TextStyle(fontSize: 11))),
                const SizedBox(width: 8),
                Text(_statusLabel(doc['status']),
                    style: const TextStyle(color: _blue, fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          const SizedBox(height: 5),
          Text(docs.length == 5 && docs.every((d) => d['status'] == 'published') ? 'Lot initial publié et archivé.' : _status?['ready'] == true
              ? 'Cinq brouillons validés, lot prêt pour la publication.'
              : 'Lot non encore validé dans son ensemble.',
              style: const TextStyle(fontSize: 11)),
        ],
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: const TextStyle(
                  color: _red, fontSize: 11))),
        if (_message != null)
          Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(_message!, style: const TextStyle(
                  color: _blue, fontSize: 11))),
        const SizedBox(height: 9),
        Wrap(spacing: 7, runSpacing: 7, children: [
          OutlinedButton.icon(
            onPressed: (_endpoint != null && !_loading && !_busy)
                ? _load : null,
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('ACTUALISER'),
          ),
          OutlinedButton.icon(
            onPressed: _canValidate ? () => _submit(publish: false) : null,
            icon: const Icon(Icons.verified_outlined, size: 17),
            label: const Text('VALIDER LE LOT'),
          ),
          FilledButton.icon(
            onPressed: _canPublish ? () => _submit(publish: true) : null,
            icon: const Icon(Icons.publish_outlined, size: 17),
            label: const Text('PUBLIER LE LOT'),
          ),
        ]),
        if (_status != null &&
            _status?['validationEnabled'] != true &&
            _status?['publicationEnabled'] != true)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Validation et publication verrouillées côté serveur '
                'jusqu’à leur activation contrôlée.',
                style: TextStyle(color: _red, fontSize: 10)),
          ),
      ]),
    );
  }
}
