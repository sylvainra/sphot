import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Acceptation contractuelle autonome de la simple consultation des CGV.
/// Aucun paiement ni commande n'est initie depuis ce composant.
class AdminCgvAcceptanceSection extends StatefulWidget {
  const AdminCgvAcceptanceSection({
    super.key,
    required this.adminUid,
  });

  final String adminUid;

  @override
  State<AdminCgvAcceptanceSection> createState() =>
      _AdminCgvAcceptanceSectionState();
}

class _AdminCgvAcceptanceSectionState extends State<AdminCgvAcceptanceSection> {
  static const _blue = Color(0xFF1E3A8A);
  static const _green = Color(0xFF16A34A);
  static const _red = Color(0xFFDC2626);
  static const _endpoint = String.fromEnvironment(
    'SPHOT_ADMIN_CGV_ACCEPTANCE_URL',
  );

  bool _consent = false;
  bool _busy = false;
  String _consentRevision = '';
  String? _message;
  String _serverAcceptedVersion = '';
  int? _serverAcceptedRevision;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final endpoint = _url;
    if (endpoint == null) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != widget.adminUid) return;
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) return;
      final response = await http.post(endpoint,
        headers: {'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'status',
          'requestId': widget.adminUid}),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return;
      final value = jsonDecode(response.body);
      if (value is! Map || value['success'] != true ||
          value['accepted'] != true || value['version'] is! String ||
          value['revision'] is! int) return;
      if (!mounted) return;
      setState(() {
        _serverAcceptedVersion = value['version'] as String;
        _serverAcceptedRevision = value['revision'] as int;
      });
    } catch (_) {
      // Le défaut de réseau n'autorise jamais à présumer une acceptation.
    }
  }

  static Uri? get _url {
    final url = Uri.tryParse(_endpoint.trim());
    if (url == null || url.scheme != 'https' || url.hasPort ||
        url.userInfo.isNotEmpty || url.query.isNotEmpty ||
        url.fragment.isNotEmpty ||
        url.host != 'us-central1-sphot-ab80b.cloudfunctions.net' ||
        url.path != '/acceptAdminCommercialCgv') {
      return null;
    }
    return url;
  }

  Future<void> _accept(String version, int revision) async {
    final endpoint = _url;
    if (_busy || endpoint == null) return;
    setState(() { _busy = true; _message = null; });
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final token = await currentUser?.getIdToken();
      if (currentUser == null || currentUser.uid != widget.adminUid ||
          token == null || token.isEmpty) {
        throw StateError('Session ADMIN requise.');
      }
      final response = await http.post(endpoint,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'requestId': widget.adminUid,
          'expectedVersion': version,
          'expectedRevision': revision,
          'accepted': true,
        }),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError('Version ou droits à vérifier ; actualisez les CGV.');
      }
      final result = jsonDecode(response.body);
      if (result is! Map || result['success'] != true ||
          result['version'] != version ||
          result['revision'] != revision) {
        throw StateError('Confirmation juridique non vérifiée.');
      }
      if (!mounted) return;
      setState(() {
        _consent = false;
        _consentRevision = '';
        _serverAcceptedVersion = version;
        _serverAcceptedRevision = revision;
        _message = 'Acceptation enregistrée pour la version $version '
            '(révision $revision). Aucune commande émise.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _message =
          'Acceptation non enregistrée. Réactualisez puis réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('legalDocuments')
          .doc('adminCgv').snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final version = data?['version']?.toString().trim() ?? '';
        final revision = data?['revision'];
        final ready = snapshot.hasData && version.isNotEmpty &&
            revision is int && revision >= 0 &&
            data?['published'] != false && data?['testOnly'] != true;
        // Seule la réponse du serveur protégé fait foi, jamais une copie
        // du consentement modifiable dans subscriptions/{uid}.
        final current = ready && _serverAcceptedVersion == version &&
            _serverAcceptedRevision == revision;
        final marker = '$version/$revision';
        final consentNow = _consent && _consentRevision == marker;

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (current)
              Text('CGV SPHOT ADMIN acceptées — version $version, '
                'révision $revision.',
                style: const TextStyle(color: _green, fontSize: 12,
                  fontWeight: FontWeight.w800))
            else if (!ready)
              const Text('CGV non publiées avec révision identifiable : '
                'acceptation indisponible.',
                style: TextStyle(color: _red, fontSize: 11))
            else if (_url == null)
              const Text('Enregistrement de l’acceptation disponible après '
                'activation du service juridique sécurisé.',
                style: TextStyle(color: _blue, fontSize: 11))
            else ...[
              CheckboxListTile(
                value: consentNow,
                contentPadding: EdgeInsets.zero,
                activeColor: _blue,
                title: Text('J’ai pris connaissance et j’accepte les '
                  'CGV SPHOT ADMIN, version $version (révision $revision).',
                  style: const TextStyle(color: _blue, fontSize: 12,
                    fontWeight: FontWeight.w700)),
                onChanged: _busy ? null : (value) => setState(() {
                  _consent = value == true;
                  _consentRevision = marker;
                  _message = null;
                }),
              ),
              OutlinedButton.icon(
                onPressed: _busy || !consentNow ? null :
                    () => _accept(version, revision as int),
                icon: _busy ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)) :
                  const Icon(Icons.verified_user_outlined),
                label: const Text('ACCEPTER LES CGV SPHOT ADMIN'),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 7),
              Text(_message!, style: const TextStyle(color: _blue,
                fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ],
        );
      },
    );
  }
}
