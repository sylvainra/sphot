import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/legal_published_version.dart';
import 'admin_legal_overlay.dart';
import '../super_admin/widgets/sphot_legal_article_markdown.dart';

enum ProfessionalLegalAudience { admin, advertiser }

Future<void> _leaveAdminLegalGate(BuildContext context) async {
  await FirebaseAuth.instance.signOut();
  if (!context.mounted) return;
  Navigator.of(context).pushNamedAndRemoveUntil(
    '/login',
    (route) => false,
  );
}

/// Le portail reste sur le bon document publié, même après une mise à jour
/// individuelle dans le dashboard Super Admin. Les brouillons ne sont jamais
/// présentés et ne modifient pas les acceptations.
class ProfessionalLegalGate extends StatefulWidget {
  const ProfessionalLegalGate({
    super.key,
    required this.audience,
    required this.child,
    this.lockedDashboard,
  });

  final ProfessionalLegalAudience audience;
  final Widget child;

  /// Décor réel du dashboard Admin pendant le verrou juridique.
  /// Le parcours PUBLICITAIRE n'utilise pas cette propriété.
  final Widget? lockedDashboard;

  @override
  State<ProfessionalLegalGate> createState() =>
      _ProfessionalLegalGateState();
}

class _ProfessionalLegalGateState extends State<ProfessionalLegalGate> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _published;

  Widget _adminStatus(
    String title,
    String detail, {
    bool loading = false,
  }) {
    return AdminLegalOverlay(
      dashboard: widget.lockedDashboard ?? widget.child,
      fullHeight: false,
      panel: AdminLegalStatusPanel(
        title: title,
        detail: detail,
        loading: loading,
        onSignOut: () => _leaveAdminLegalGate(context),
      ),
    );
  }


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
          if (widget.audience == ProfessionalLegalAudience.admin) {
            return _adminStatus(
              'Document juridique momentanément inaccessible',
              'Impossible de vérifier les CGU SPHOT ADMIN.',
            );
          }
          return _GateMessage(
            title: 'Document juridique momentanément inaccessible',
            detail: 'Impossible de vérifier les CGU $_displayName.',
          );
        }
        if (!snapshot.hasData) {
          if (widget.audience == ProfessionalLegalAudience.admin) {
            return _adminStatus(
              'Vérification de vos CGU',
              'Chargement de la version publiée…',
              loading: true,
            );
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!.data();
        if (data == null || data['published'] != true ||
            data['testOnly'] == true) {
          // Le portail ADMIN ne présente jamais un accès libre si son texte
          // juridique actif est indisponible. L'annonceur reste inchangé.
          if (widget.audience == ProfessionalLegalAudience.admin) {
            return _adminStatus(
              'CGU SPHOT ADMIN indisponibles',
              'Le document juridique publié est introuvable. '
                  'Réessayez ultérieurement ou déconnectez-vous.',
            );
          }
          return widget.child;
        }
        if (!LegalPublishedVersion.isPublishedDocument(
              data,
              chapterCount: _chapterCount,
            )) {
          if (widget.audience == ProfessionalLegalAudience.admin) {
            return _adminStatus(
              'Version juridique incomplète',
              'Les 14 articles CGU ADMIN doivent être vérifiés '
                  'par l’équipe SPHOT.',
            );
          }
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
          lockedDashboard: widget.audience == ProfessionalLegalAudience.admin
              ? widget.lockedDashboard
              : null,
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
    this.lockedDashboard,
  });

  final String documentId;
  final String displayName;
  final String versionId;
  final List<Map<String, dynamic>> chapters;
  final Widget child;
  final Widget? lockedDashboard;

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
  bool _adminShowFullDocument = false;
  Map<String, dynamic>? _adminChanges;
  Map<String, dynamic>? _advertiserChanges;
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
        _adminChanges = widget.documentId == 'adminCgu' &&
                result['adminChanges'] is Map
            ? Map<String, dynamic>.from(result['adminChanges'] as Map)
            : null;
        _advertiserChanges = widget.documentId == 'advertiserCgu' &&
                result['advertiserChanges'] is Map
            ? Map<String, dynamic>.from(result['advertiserChanges'] as Map)
            : null;
        _adminShowFullDocument = false;
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


  List<Map<String, dynamic>> get _adminModifiedArticles {
    final rows = _adminChanges?['articles'];
    if (rows is! List) return <Map<String, dynamic>>[];
    return rows.whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row)).toList();
  }

  List<Map<String, dynamic>> get _advertiserModifiedArticles {
    final rows = _advertiserChanges?['articles'];
    if (rows is! List) return <Map<String, dynamic>>[];
    return rows.whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Widget _adminChangedArticle(Map<String, dynamic> article) {
    const blue = Color(0xFF213F8E);
    const purple = Color(0xFF6544A8);
    final id = (article['id'] ?? '').toString();
    final title = (article['title'] ?? '').toString();
    final blocks = (article['blocks'] is List)
        ? (article['blocks'] as List).whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row)).toList()
        : <Map<String, dynamic>>[];
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      color: const Color(0xFFF7F8FC),
      child: ExpansionTile(
        initiallyExpanded: (widget.documentId == 'adminCgu'
            ? _adminModifiedArticles.length
            : _advertiserModifiedArticles.length) <= 3,
        title: Text('Article $id — $title',
          style: const TextStyle(color: blue, fontSize: 13,
            fontWeight: FontWeight.w800)),
        childrenPadding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
        children: [
          if (article['titleChanged'] == true) ...[
            const Text('TITRE MODIFIÉ', style: TextStyle(
              color: purple, fontWeight: FontWeight.bold)),
            Text('Ancien titre : ${article['beforeTitle'] ?? ''}'),
          ],
          if (article['orderChanged'] == true)
            const Text('Ordre des articles modifié.'),
          ...blocks.map((block) {
            final before = (block['before'] ?? '').toString();
            final after = (block['after'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(after.isEmpty ? 'PASSAGE SUPPRIMÉ'
                      : before.isEmpty ? 'PASSAGE AJOUTÉ'
                      : 'NOUVELLE FORMULATION',
                    style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w900, color: purple)),
                  const SizedBox(height: 6),
                  if (after.isNotEmpty)
                    SphotLegalArticleMarkdown(markdown: after)
                  else
                    const Text('Ce passage a été retiré des CGU.'),
                  if (before.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Consulter l’ancienne rédaction',
                        style: TextStyle(color: blue, fontSize: 12)),
                      children: [
                        Align(alignment: Alignment.centerLeft,
                          child: SphotLegalArticleMarkdown(markdown: before)),
                      ],
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _adminAcceptancePanel({bool advertiser = false}) {
    const blue = Color(0xFF213F8E);
    const purple = Color(0xFF6544A8);
    final changeData = advertiser ? _advertiserChanges : _adminChanges;
    final changes =
        advertiser ? _advertiserModifiedArticles : _adminModifiedArticles;
    final targeted = changes.isNotEmpty;
    final oldVersion = (changeData?['baselineVersionId'] ?? '').toString();
    final acceptedBaseline =
        changeData?['baselineKind'] == 'lastAccepted';
    final full = _adminShowFullDocument || !targeted;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(17, 14, 17, 13),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF18356F), Color(0xFF3154A1)])),
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined,
                color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MODIFICATIONS DES CGU ${widget.displayName}',
                    style: const TextStyle(fontSize: 15,
                      fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 3),
                  Text('Version publiée ${widget.versionId}',
                    style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700, color: Color(0xFFE1E9FF))),
                ],
              )),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
            children: [
              if (targeted) ...[
                Text('${changes.length} article(s) modifié(s)',
                  style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800, color: blue)),
                const SizedBox(height: 8),
                Text(acceptedBaseline
                    ? 'Comparaison avec la version précédemment acceptée '
                      '($oldVersion). Seuls les passages modifiés sont affichés.'
                    : 'Modifications de la dernière publication, comparées '
                      'à la version $oldVersion. L’ancienne acceptation '
                      'de ce compte n’est pas identifiable dans ce registre.',
                  style: const TextStyle(fontSize: 12, height: 1.35,
                    color: blue)),
                const SizedBox(height: 12),
                ...changes.map(_adminChangedArticle),
                TextButton.icon(
                  onPressed: () => setState(() =>
                    _adminShowFullDocument = !_adminShowFullDocument),
                  icon: Icon(_adminShowFullDocument
                      ? Icons.expand_less : Icons.menu_book_outlined),
                  label: Text(_adminShowFullDocument
                      ? 'MASQUER LES CGU COMPLÈTES'
                      : 'CONSULTER LES ${widget.chapters.length} ARTICLES '
                        'DES CGU COMPLÈTES'),
                ),
              ] else ...[
                const Text('Comparaison historique indisponible ou '
                    'sans différence textuelle : consultez les CGU '
                    'complètes avant de les accepter.',
                  style: TextStyle(fontSize: 13, color: blue)),
                const SizedBox(height: 12),
              ],
              if (full)
                ...widget.chapters.map((chapter) => Card(
                  margin: const EdgeInsets.only(bottom: 7),
                  color: const Color(0xFFF6F7FB),
                  child: ExpansionTile(
                    title: Text((chapter['title'] ?? '').toString(),
                      style: const TextStyle(color: blue,
                        fontSize: 13, fontWeight: FontWeight.w700)),
                    childrenPadding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
                    children: [
                      SphotLegalArticleMarkdown(
                        markdown: (chapter['content'] ?? '').toString()),
                    ],
                  ),
                )),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 9),
          decoration: const BoxDecoration(
            color: Color(0xFFF5F7FB),
            border: Border(top: BorderSide(color: Color(0xFFD8DFEB)))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: purple,
                value: _acknowledged,
                onChanged: _submitting ? null : (value) =>
                  setState(() => _acknowledged = value ?? false),
                title: Text('J’ai pris connaissance des modifications et '
                    'j’accepte l’intégralité des CGU ${widget.displayName}, '
                    'version ${widget.versionId}.',
                  style: const TextStyle(color: blue, fontSize: 12,
                    fontWeight: FontWeight.w600)),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 6,
                children: [
                  TextButton.icon(
                    onPressed: _submitting ? null :
                      () => _leaveAdminLegalGate(context),
                    icon: const Icon(Icons.logout_outlined, size: 17),
                    label: const Text('SE DÉCONNECTER')),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: purple),
                    onPressed: !_acknowledged || _submitting ? null : _accept,
                    icon: const Icon(Icons.check_circle_outline, size: 17),
                    label: Text(_submitting
                        ? 'ENREGISTREMENT…' : 'ACCEPTER ET CONTINUER')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _adminLockedDashboard({bool advertiser = false}) {
    final status = _loading
        ? AdminLegalStatusPanel(
            title: 'Vérification des CGU ${widget.displayName}',
            detail: 'Chargement de votre acceptation…',
            loading: true,
            onSignOut: () => _leaveAdminLegalGate(context),
          )
        : _error != null
            ? AdminLegalStatusPanel(
                title: 'Vérification des CGU impossible',
                detail: _error.toString(),
                onRetry: _check,
                onSignOut: () => _leaveAdminLegalGate(context),
              )
            : _adminAcceptancePanel(advertiser: advertiser);

    return AdminLegalOverlay(
      dashboard: widget.lockedDashboard ?? widget.child,
      fullHeight: !_loading && _error == null,
      panel: status,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Les parcours professionnels approuvés partagent le même panneau
    // juridique bloquant. Le dashboard reste visible derrière la carte et
    // ses étapes, quel que soit le document à réaccepter.
    if (widget.documentId == 'adminCgu' ||
        widget.documentId == 'advertiserCgu') {
      if (!_loading && _error == null && !_required) return widget.child;
      return _adminLockedDashboard(
        advertiser: widget.documentId == 'advertiserCgu',
      );
    }

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
