import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/legal_published_version.dart';
import '../super_admin/widgets/sphot_legal_article_markdown.dart';

enum ProfessionalLegalAudience { admin, advertiser }

/// Le portail reste sur le bon document publié, même après une mise à jour
/// individuelle dans le dashboard Super Admin. Les brouillons ne sont jamais
/// présentés et ne modifient pas les acceptations.
class ProfessionalLegalGate extends StatelessWidget {
  const ProfessionalLegalGate({
    super.key,
    required this.audience,
    required this.child,
  });

  final ProfessionalLegalAudience audience;
  final Widget child;

  String get _documentId => audience == ProfessionalLegalAudience.admin
      ? 'adminCgu'
      : 'advertiserCgu';

  int get _chapterCount => audience == ProfessionalLegalAudience.admin
      ? 14
      : 12;

  String get _displayName => audience == ProfessionalLegalAudience.admin
      ? 'SPHOT ADMIN'
      : 'SPHOT PUBLICITAIRE';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('legalDocuments').doc(_documentId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _GateMessage(
            title: 'Document juridique momentanément inaccessible',
            detail: 'Impossible de vérifier les CGU $_displayName.',
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!.data();
        if (data == null || data['published'] != true ||
            data['testOnly'] == true) {
          // Avant la première publication, les accès existants sont préservés.
          return child;
        }
        if (!LegalPublishedVersion.isPublishedDocument(
              data,
              chapterCount: _chapterCount,
            )) {
          return _GateMessage(
            title: 'Version juridique incomplète',
            detail: 'Les CGU $_displayName sont publiées mais '
                'leur contenu doit être vérifié par l’équipe SPHOT.',
          );
        }
        final versionId = LegalPublishedVersion.identifier(
          data,
          fallback: '',
        );
        return _PublishedProfessionalLegalGate(
          key: ValueKey('$_documentId:$versionId'),
          documentId: _documentId,
          displayName: _displayName,
          versionId: versionId,
          chapters: (data['chapters'] as List)
              .whereType<Map>()
              .map((part) => Map<String, dynamic>.from(part))
              .toList(),
          child: child,
        );
      },
    );
  }
}

class _PublishedProfessionalLegalGate extends StatefulWidget {
  const _PublishedProfessionalLegalGate({
    super.key,
    required this.documentId,
    required this.displayName,
    required this.versionId,
    required this.chapters,
    required this.child,
  });

  final String documentId;
  final String displayName;
  final String versionId;
  final List<Map<String, dynamic>> chapters;
  final Widget child;

  @override
  State<_PublishedProfessionalLegalGate> createState() =>
      _PublishedProfessionalLegalGateState();
}

class _PublishedProfessionalLegalGateState
    extends State<_PublishedProfessionalLegalGate> {
  static const _endpoint =
      'https://us-central1-sphot-ab80b.cloudfunctions.net/'
      'acceptSphotProfessionalLegal';

  bool _loading = true;
  bool _submitting = false;
  bool _required = true;
  bool _acknowledged = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<Map<String, dynamic>> _server(
    Map<String, dynamic> payload,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Connexion professionnelle Firebase requise.');
    }
    final bearer = await user.getIdToken();
    if (bearer == null || bearer.isEmpty) {
      throw StateError('Session professionnelle indisponible.');
    }
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Authorization': 'Bearer $bearer',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 25));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['success'] != true ||
        response.statusCode != 200) {
      final code = decoded is Map
          ? (decoded['error'] ?? '').toString()
          : '';
      if (response.statusCode == 409) {
        throw StateError('La version des CGU a changé. Rechargez la page.');
      }
      throw StateError('Vérification juridique impossible '
          '(HTTP ${response.statusCode}, $code).');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _server({'action': 'status'});
      if (!mounted) return;
      if (result['published'] != true ||
          result['documentId'] != widget.documentId ||
          result['versionId'] != widget.versionId) {
        throw StateError('Version publiée en cours de synchronisation.');
      }
      setState(() {
        _required = result['required'] == true;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _accept() async {
    if (!_acknowledged || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await _server({
        'action': 'accept',
        'versionId': widget.versionId,
        'accepted': true,
      });
      if (!mounted) return;
      if (result['accepted'] != true ||
          result['versionId'] != widget.versionId) {
        throw StateError('Preuve d’acceptation non confirmée.');
      }
      setState(() {
        _required = false;
        _submitting = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _GateMessage(
        title: 'Vérification des CGU $_error',
        detail: 'La version publiée est conservée. '
            'Aucune acceptation n’a été enregistrée.',
        onRetry: _check,
      );
    }
    if (!_required) return widget.child;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('CONDITIONS GÉNÉRALES D’UTILISATION — '
                  '${widget.displayName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E3A8A),
                    fontSize: 23,
                  )),
              const SizedBox(height: 8),
              Text('Version publiée ${widget.versionId}. '
                  'Les CGU ont été mises à jour depuis le portail '
                  'Super Admin. Leur acceptation est nécessaire '
                  'pour poursuivre.'),
              const SizedBox(height: 16),
              ...widget.chapters.map((chapter) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ExpansionTile(
                  title: Text(
                    (chapter['title'] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  childrenPadding: const EdgeInsets.all(16),
                  children: [
                    SphotLegalArticleMarkdown(
                      markdown: (chapter['content'] ?? '').toString(),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 14),
              CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                value: _acknowledged,
                onChanged: (checked) => setState(
                  () => _acknowledged = checked ?? false,
                ),
                title: Text('J’ai lu et j’accepte les CGU '
                    '${widget.displayName}, version '
                    '${widget.versionId}.'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: !_acknowledged || _submitting ? null : _accept,
                child: Text(_submitting
                    ? 'ENREGISTREMENT…'
                    : 'ACCEPTER ET CONTINUER'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GateMessage extends StatelessWidget {
  const _GateMessage({
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(detail, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('RÉESSAYER'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
