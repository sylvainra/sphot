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
class ProfessionalLegalGate extends StatefulWidget {
  const ProfessionalLegalGate({
    super.key,
    required this.audience,
    required this.child,
  });

  final ProfessionalLegalAudience audience;
  final Widget child;

  @override
  State<ProfessionalLegalGate> createState() =>
      _ProfessionalLegalGateState();
}

class _ProfessionalLegalGateState extends State<ProfessionalLegalGate> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _published;

  String get _documentId =>
      widget.audience == ProfessionalLegalAudience.admin
          ? 'adminCgu'
          : 'advertiserCgu';

  int get _chapterCount =>
      widget.audience == ProfessionalLegalAudience.admin ? 14 : 12;

  String get _displayName =>
      widget.audience == ProfessionalLegalAudience.admin
          ? 'SPHOT ADMIN'
          : 'SPHOT PUBLICITAIRE';

  @override
  void initState() {
    super.initState();
    // Une seule souscription pendant la vie du dashboard. La carte peut
    // se reconstruire souvent sans provoquer de rechargement juridique.
    _published = FirebaseFirestore.instance
        .collection('legalDocuments').doc(_documentId).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _published,
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
          return widget.child;
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
          child: widget.child,
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


  static const _blue = Color(0xFF1E3A8A);
  static const _darkBlue = Color(0xFF12295E);
  static const _orange = Color(0xFFF59E0B);

  Widget _articleCard(int index, Map<String, dynamic> chapter) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD5DFEF), width: 1.2),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: _blue.withOpacity(0.07),
        ),
        child: ExpansionTile(
          key: PageStorageKey<String>(
            'professional-legal-' + widget.documentId + '-' +
                index.toString(),
          ),
          tilePadding: const EdgeInsets.fromLTRB(16, 5, 14, 5),
          childrenPadding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
          iconColor: _blue,
          collapsedIconColor: _blue,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0FC),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: _blue,
              size: 21,
            ),
          ),
          title: Text(
            (chapter['title'] ?? '').toString(),
            style: const TextStyle(
              color: _darkBlue,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          children: [
            SizedBox(
              width: double.infinity,
              child: SphotLegalArticleMarkdown(
                markdown: (chapter['content'] ?? '').toString(),
                style: const TextStyle(
                  color: Color(0xFF25334A),
                  fontSize: 15.5,
                  height: 1.65,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legalHeader(bool compact) {
    final heading = Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'CONDITIONS GÉNÉRALES D’UTILISATION',
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 18 : 23,
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.displayName,
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: const TextStyle(
            color: _orange,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 30,
        compact ? 16 : 22,
        compact ? 18 : 30,
        compact ? 16 : 22,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_blue, _darkBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: _orange, width: 3)),
      ),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'data/icons/title.png',
                  height: 50,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 9),
                heading,
              ],
            )
          : Row(
              children: [
                Image.asset(
                  'data/icons/title.png',
                  width: 178,
                  height: 65,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 26),
                Expanded(child: heading),
              ],
            ),
    );
  }

  Widget _legalFooter(bool compact) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 24,
        11,
        compact ? 14 : 24,
        compact ? 14 : 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFD5DFEF), width: 1.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _submitting
                ? null
                : () => setState(() => _acknowledged = !_acknowledged),
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                Checkbox(
                  value: _acknowledged,
                  activeColor: _blue,
                  onChanged: _submitting
                      ? null
                      : (checked) => setState(
                          () => _acknowledged = checked ?? false,
                        ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'J’ai lu et j’accepte les CGU ' + widget.displayName +
                        ', version ' + widget.versionId + '.',
                    style: const TextStyle(
                      color: _darkBlue,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: !_acknowledged || _submitting ? null : _accept,
              icon: _submitting
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Icon(Icons.verified_user_rounded, size: 21),
              label: Text(
                _submitting
                    ? 'ENREGISTREMENT EN COURS…'
                    : 'ACCEPTER ET CONTINUER',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFD5DCE9),
                disabledForegroundColor: const Color(0xFF637087),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legalReview(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FD),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'data/images/map_background.jpg',
              fit: BoxFit.cover,
            ),
            const ColoredBox(color: Color(0xEAF4F7FC)),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 680;
                  final margin = compact ? 12.0 : 24.0;
                  final width = constraints.maxWidth > 988
                      ? 940.0
                      : constraints.maxWidth - 2 * margin;
                  final height = constraints.maxHeight > 860
                      ? 820.0
                      : constraints.maxHeight - (compact ? 16 : 30);

                  return Center(
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F9FE),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: _blue, width: 1.8),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x220B234B),
                              blurRadius: 28,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _legalHeader(compact),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 16 : 26,
                                vertical: 13,
                              ),
                              color: const Color(0xFFEAF0FC),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline_rounded,
                                    color: _blue,
                                    size: 23,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Version publiée ' + widget.versionId +
                                          ' — ' +
                                          widget.chapters.length.toString() +
                                          ' articles. Les CGU ont été mises '
                                          'à jour. Leur acceptation est '
                                          'nécessaire pour poursuivre.',
                                      style: const TextStyle(
                                        color: _darkBlue,
                                        fontSize: 14,
                                        height: 1.45,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Scrollbar(
                                child: ListView.builder(
                                  padding: EdgeInsets.fromLTRB(
                                    compact ? 12 : 24,
                                    18,
                                    compact ? 12 : 24,
                                    16,
                                  ),
                                  itemCount: widget.chapters.length,
                                  itemBuilder: (context, index) =>
                                      _articleCard(
                                    index,
                                    widget.chapters[index],
                                  ),
                                ),
                              ),
                            ),
                            _legalFooter(compact),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
        title: 'Vérification des CGU ' + _error!,
        detail: 'La version publiée est conservée. '
            'Aucune acceptation n’a été enregistrée.',
        onRetry: _check,
      );
    }
    if (!_required) return widget.child;
    return _legalReview(context);
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
