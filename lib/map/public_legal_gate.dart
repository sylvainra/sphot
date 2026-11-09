import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/public_legal_acceptance_service.dart';
import '../widgets/fire_icon_assets.dart';

/// Accueil juridique du grand public, commun à Flutter mobile et Flutter Web.
/// Les routes professionnelles conservent leurs propres contrôles juridiques.
class PublicLegalGate extends StatefulWidget {
  const PublicLegalGate({
    super.key,
    required this.child,
    this.loadDocuments,
  });

  final Widget child;
  /// Permet de vérifier le parcours sans interroger Firestore pendant les tests.
  final Future<List<PublicLegalDocument>> Function()? loadDocuments;

  @override
  State<PublicLegalGate> createState() => _PublicLegalGateState();
}

enum _PublicLegalStage { loading, accept, informationUpdate, ready, error }

class _PublicLegalGateState extends State<PublicLegalGate> {
  static const _blue = Color(0xFF1E3A8A);
  static const _orange = Color(0xFFFF8500);

  final _acceptanceService = const PublicLegalAcceptanceService();
  _PublicLegalStage _stage = _PublicLegalStage.loading;
  Map<String, PublicLegalDocument> _documents = {};
  PublicLegalVersions? _versions;
  bool _checked = false;
  bool _saving = false;
  bool _showLoadingCard = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrentDocuments();
  }

  Future<void> _loadCurrentDocuments() async {
    setState(() {
      _stage = _PublicLegalStage.loading;
      _showLoadingCard = false;
      _error = null;
      _checked = false;
    });

    try {
      final alreadyAccepted =
          await _acceptanceService.hasRecordedCguAcceptance();
      if (!mounted) return;
      setState(() => _showLoadingCard = !alreadyAccepted);

      final loaded = await (widget.loadDocuments?.call() ?? Future.wait([
        PublicLegalDocument.load('cgu', 'Conditions Générales d’Utilisation'),
        PublicLegalDocument.load(
          'privacyPolicy',
          'Politique de confidentialité',
        ),
        PublicLegalDocument.load('rgpdNotice', 'Notice RGPD'),
      ]));
      final documents = {for (final document in loaded) document.id: document};
      final versions = PublicLegalVersions(
        cgu: documents['cgu']!.versionId,
        privacyPolicy: documents['privacyPolicy']!.versionId,
        rgpdNotice: documents['rgpdNotice']!.versionId,
      );
      final decision = await _acceptanceService.accessDecision(versions);

      if (!mounted) return;
      setState(() {
        _documents = documents;
        _versions = versions;
        _stage = switch (decision) {
          PublicLegalAccessDecision.acceptCgu => _PublicLegalStage.accept,
          PublicLegalAccessDecision.acknowledgeInformationUpdate =>
            _PublicLegalStage.informationUpdate,
          PublicLegalAccessDecision.allowAccess => _PublicLegalStage.ready,
        };
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _PublicLegalStage.error;
        _error = 'Impossible de charger les documents juridiques pour le moment. '
            'Veuillez réessayer.';
      });
      debugPrint('Chargement des documents grand public impossible : $error');
    }
  }

  Future<void> _continue() async {
    final versions = _versions;
    if (versions == null || _saving) return;
    if (_stage == _PublicLegalStage.accept && !_checked) return;

    final stage = _stage;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (stage == _PublicLegalStage.accept) {
        await _acceptanceService.accept(versions);
      } else if (stage == _PublicLegalStage.informationUpdate) {
        await _acceptanceService.acknowledgeInformationUpdate(versions);
      }
      if (!mounted) return;
      setState(() => _stage = _PublicLegalStage.ready);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de mémoriser votre choix sur cet appareil. '
            'Veuillez réessayer.';
      });
      debugPrint('Enregistrement de l’acceptation publique impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showDocument(String id) async {
    final document = _documents[id];
    if (document == null) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(document.title, style: const TextStyle(color: _blue)),
        content: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(dialogContext).height * 0.62,
          child: ListView(
            children: [
              Text(
                document.revision >= 0
                    ? 'Version ${document.version} — révision ${document.revision}'
                    : 'Version ${document.version} — édition historique',
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              for (final chapter in document.chapters)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapter.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _blue,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(chapter.content),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('FERMER'),
          ),
        ],
      ),
    );
  }

  Widget _documentButton(String id, IconData icon, String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _showDocument(id),
        icon: Icon(icon, size: 19),
        label: Text(label, textAlign: TextAlign.left),
        style: TextButton.styleFrom(
          foregroundColor: _blue,
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        ),
      ),
    );
  }

  Widget _buildCard() {
    final stage = _stage;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 12,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SvgPicture.asset(
              FireIconAssets.red,
              width: 42,
              height: 58,
            ),
            const SizedBox(height: 8),
            const Text(
              'BIENVENUE SUR SPHOT',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _blue,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 15),
            if (stage == _PublicLegalStage.loading) ...[
              const Center(child: CircularProgressIndicator(color: _orange)),
              const SizedBox(height: 14),
              const Text(
                'Vérification des documents juridiques publiés…',
                textAlign: TextAlign.center,
              ),
            ] else if (stage == _PublicLegalStage.error) ...[
              Text(_error ?? 'Chargement impossible.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadCurrentDocuments,
                child: const Text('RÉESSAYER'),
              ),
            ] else ...[
              Text(
                stage == _PublicLegalStage.accept
                    ? 'Avant de consulter la carte, merci de prendre '
                        'connaissance de nos conditions d’utilisation et '
                        'des informations sur vos données personnelles.'
                    : 'Nos informations sur la protection des données '
                        'personnelles ont été mises à jour. Vous pouvez '
                        'les consulter ci-dessous.',
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.35),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F6FC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      _documentButton('cgu', Icons.description_outlined, 'CGU — Grand public'),
                      _documentButton(
                        'privacyPolicy',
                        Icons.privacy_tip_outlined,
                        'Politique de confidentialité',
                      ),
                      _documentButton('rgpdNotice', Icons.lock_outline, 'Notice RGPD'),
                    ],
                  ),
                ),
              ),
              if (stage == _PublicLegalStage.accept) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _checked,
                  onChanged: _saving
                      ? null
                      : (checked) => setState(() => _checked = checked ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'J’accepte les CGU de SPHOT et reconnais avoir pris '
                    'connaissance de la Politique de confidentialité '
                    'et de la Notice RGPD.',
                    style: TextStyle(fontSize: 13, height: 1.3),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _saving ||
                        (stage == _PublicLegalStage.accept && !_checked)
                    ? null
                    : _continue,
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(stage == _PublicLegalStage.accept
                        ? 'ACCEPTER ET CONTINUER'
                        : 'J’AI COMPRIS'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_stage != _PublicLegalStage.ready) ...[
          ModalBarrier(
            key: const Key('public-legal-access-barrier'),
            color: _stage == _PublicLegalStage.loading && !_showLoadingCard
                ? Colors.transparent
                : const Color(0x99000000),
            dismissible: false,
          ),
          if (_stage != _PublicLegalStage.loading || _showLoadingCard)
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: _buildCard(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class PublicLegalDocument {
  const PublicLegalDocument({
    required this.id,
    required this.title,
    required this.version,
    required this.revision,
    required this.chapters,
  });

  final String id;
  final String title;
  final String version;
  final int revision;
  final List<PublicLegalChapter> chapters;

  String get versionId => revision >= 0
      ? '$version:r$revision'
      : '$version:historique';

  /// Les textes communs existaient avant la publication C4 : leur version
  /// individuelle ou leur révision peuvent manquer. Le numéro global est
  /// celui déjà utilisé par la page Profil pour ces textes historiques.
  /// Les CGU Grand Public restent soumises au versionnement strict.
  static ({String version, int revision}) resolveVersion(
    String id,
    Map<String, dynamic> data, {
    String? globalVersion,
  }) {
    final isCommon = id == 'privacyPolicy' || id == 'rgpdNotice';
    final individualVersion = (data['version'] ?? '').toString().trim();
    final fallback = (globalVersion ?? '').trim();
    final version = individualVersion.isNotEmpty
        ? individualVersion
        : (isCommon ? fallback : '');
    final rawRevision = data['revision'];
    final revision = rawRevision is int && rawRevision >= 0
        ? rawRevision
        : -1;
    if (version.isEmpty || (!isCommon && revision < 0)) {
      throw StateError('Version juridique invalide : $id');
    }
    return (version: version, revision: revision);
  }

  /// Les notices communes sont des documents actifs historiques : le champ
  /// `published` peut y être absent. À l'inverse, les CGU Grand Public du
  /// paquet publié C4 doivent explicitement porter `published: true`.
  static bool isEligibleLiveDocument(String id, Map<String, dynamic>? data) {
    if (data == null || data['testOnly'] == true) return false;
    if (id == 'cgu') return data['published'] == true;
    if (id == 'privacyPolicy' || id == 'rgpdNotice') {
      return !data.containsKey('published') || data['published'] == true;
    }
    return false;
  }

  static Future<PublicLegalDocument> load(String id, String title) async {
    final reference = FirebaseFirestore.instance.collection('legalDocuments').doc(id);
    final snapshot = await reference.get();
    final data = snapshot.data();
    if (data == null || !isEligibleLiveDocument(id, data)) {
      throw StateError('Document juridique non publié : $id');
    }

    String? globalVersion;
    if (id != 'cgu' && (data['version'] ?? '').toString().trim().isEmpty) {
      final metadataSnapshot = await FirebaseFirestore.instance
          .collection('legalDocuments')
          .doc('metadata')
          .get();
      final metadata = metadataSnapshot.data() ?? {};
      globalVersion = (metadata['legalVersion'] ??
              metadata['version'] ??
              metadata['activeVersion'] ??
              '1.0')
          .toString()
          .trim();
    }
    final resolved = resolveVersion(id, data, globalVersion: globalVersion);

    final chapters = <PublicLegalChapter>[];
    final inlineChapters = data['chapters'];
    if (inlineChapters is List) {
      for (var index = 0; index < inlineChapters.length; index++) {
        final value = inlineChapters[index];
        if (value is Map) {
          chapters.add(PublicLegalChapter.fromMap(
            Map<String, dynamic>.from(value),
            index + 1,
          ));
        }
      }
    }

    if (chapters.isEmpty) {
      final chapterSnapshot = await reference.collection('chapters').get();
      for (var index = 0; index < chapterSnapshot.docs.length; index++) {
        chapters.add(PublicLegalChapter.fromMap(
          chapterSnapshot.docs[index].data(),
          index + 1,
        ));
      }
    }

    chapters.removeWhere((chapter) => chapter.content.trim().isEmpty);
    chapters.sort((a, b) => a.order.compareTo(b.order));
    if (chapters.isEmpty) {
      throw StateError('Document juridique sans texte : $id');
    }

    return PublicLegalDocument(
      id: id,
      title: title,
      version: resolved.version,
      revision: resolved.revision,
      chapters: chapters,
    );
  }
}

class PublicLegalChapter {
  const PublicLegalChapter({
    required this.title,
    required this.content,
    required this.order,
  });

  final String title;
  final String content;
  final int order;

  factory PublicLegalChapter.fromMap(Map<String, dynamic> data, int fallbackOrder) {
    final rawOrder = data['order'];
    return PublicLegalChapter(
      title: (data['title'] ?? data['titre'] ?? '').toString().trim(),
      content: (data['content'] ?? data['texte'] ?? '').toString().trim(),
      order: rawOrder is num ? rawOrder.toInt() : fallbackOrder,
    );
  }
}
