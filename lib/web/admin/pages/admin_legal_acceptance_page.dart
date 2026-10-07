import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../shared/sphot_access_page.dart';

class AdminLegalAcceptancePage extends StatefulWidget {
  const AdminLegalAcceptancePage({super.key});

  @override
  State<AdminLegalAcceptancePage> createState() =>
      _AdminLegalAcceptancePageState();
}

class _AdminLegalAcceptancePageState
    extends State<AdminLegalAcceptancePage> {
  final ExpansionTileController _cguController = ExpansionTileController();
  final ExpansionTileController _privacyController = ExpansionTileController();
  final ExpansionTileController _rgpdController = ExpansionTileController();

  Map<String, dynamic>? _cguDocument;
  Map<String, dynamic>? _privacyDocument;
  Map<String, dynamic>? _rgpdDocument;

  bool _loading = true;
  bool _saving = false;
  bool _representativeAccepted = false;
  bool _responsibilityAccepted = false;
  bool _cguAccepted = false;
  bool _privacyAccepted = false;
  bool _rgpdAccepted = false;

  String _version = '1.0';
  dynamic _publishedAt;
  String _legalPackPath = '';
  String? _error;

  bool get _canContinue =>
      !_loading &&
      !_saving &&
      _representativeAccepted &&
      _responsibilityAccepted &&
      _cguAccepted &&
      _privacyAccepted &&
      _rgpdAccepted;

  @override
  void initState() {
    super.initState();
    _loadLegalDocuments();
  }

  Future<Map<String, dynamic>> _loadLegalDocument(String documentId) async {
    final firestore = FirebaseFirestore.instance;
    final document =
        await firestore.collection('legalDocuments').doc(documentId).get();
    final chapters = await firestore
        .collection('legalDocuments')
        .doc(documentId)
        .collection('chapters')
        .orderBy(FieldPath.documentId)
        .get();

    return <String, dynamic>{
      ...?document.data(),
      'chapters': chapters.docs.map((chapter) => chapter.data()).toList(),
    };
  }

  Future<void> _loadLegalDocuments() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final metadata =
          await firestore.collection('legalDocuments').doc('metadata').get();

      final results = await Future.wait<Map<String, dynamic>>([
        _loadLegalDocument('cgu'),
        _loadLegalDocument('privacyPolicy'),
        _loadLegalDocument('rgpdNotice'),
      ]);

      final metadataData = metadata.data() ?? <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _version =
            (metadataData['legalVersion'] ??
                    metadataData['version'] ??
                    metadataData['activeVersion'] ??
                    '1.0')
                .toString();
        _publishedAt = metadataData['publishedAt'];
        _legalPackPath = (metadataData['packPath'] ?? '').toString();
        _cguDocument = results[0];
        _privacyDocument = results[1];
        _rgpdDocument = results[2];
        _loading = false;
      });
    } catch (error) {
      debugPrint('Chargement juridique Admin impossible : $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les règles applicables.';
      });
    }
  }

  Future<void> _acceptAndContinue() async {
    if (!_canContinue) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final reference = firestore.collection('adminRequests').doc();
      final legalVersionId = _version.trim().replaceAll('.', '_');

      await reference.set({
        'uid': reference.id,
        'status': 'draft',
        'accessPhase': 'draft',
        'trialRequest': {
          'trialDurationDays': 8,
          'certifyRepresentative': true,
          'adminResponsibilityAccepted': true,
          'legalReadConfirmed': true,
          'privacyReadConfirmed': true,
          'rgpdAccepted': true,
          'acceptedDocuments': {
            'version': _version,
            'publishedAt': _publishedAt,
            'acceptedAt': FieldValue.serverTimestamp(),
            'cgu': true,
            'privacy': true,
            'rgpd': true,
          },
        },
        'legalAcceptance': {
          'accepted': true,
          'version': _version,
          'legalVersion': _version,
          'legalVersionId': legalVersionId,
          'legalPackPath': _legalPackPath.isNotEmpty
              ? _legalPackPath
              : 'legalPacks/versions/items/$legalVersionId',
          'publishedAt': _publishedAt,
          'acceptedAt': FieldValue.serverTimestamp(),
          'representativeDeclaration': true,
          'adminResponsibilityDeclaration': true,
          'documents': {
            'cgu': true,
            'privacy': true,
            'rgpd': true,
          },
        },
        'legalPreAcceptanceCompleted': true,
        'legalPreAcceptanceVersion': _version,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        '/admin-request-form?requestId=${reference.id}',
      );
    } catch (error) {
      debugPrint('Enregistrement juridique Admin impossible : $error');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'Impossible d’enregistrer votre acceptation. Réessayez.';
      });
    }
  }

  Widget _acceptanceLine({
    required bool value,
    required String text,
    required ValueChanged<bool?> onChanged,
  }) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      activeColor: sphotAccessBlue,
      checkColor: Colors.white,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      horizontalTitleGap: 0,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -2),
      title: Text(
        text,
        style: const TextStyle(
          color: sphotAccessBlue,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
    );
  }

  Widget _legalDocument({
    required String title,
    required Map<String, dynamic>? document,
    required bool accepted,
    required String acceptanceText,
    required ExpansionTileController controller,
    required ValueChanged<bool?> onChanged,
  }) {
    final chapters = List<Map<String, dynamic>>.from(
      document?['chapters'] ?? const [],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.80),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sphotAccessBlue, width: 1.2),
      ),
      child: ExpansionTile(
        controller: controller,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(
          title,
          style: const TextStyle(
            color: sphotAccessBlue,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: chapters.isEmpty
                  ? const [
                      Text(
                        'Aucun chapitre renseigné.',
                        style: TextStyle(
                          color: sphotAccessBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ]
                  : chapters.map((chapter) {
                      final chapterTitle =
                          (chapter['title'] ?? chapter['titre'] ?? '')
                              .toString();
                      final chapterContent =
                          (chapter['content'] ?? chapter['texte'] ?? '')
                              .toString();

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (chapterTitle.isNotEmpty)
                              Text(
                                chapterTitle,
                                style: const TextStyle(
                                  color: Color(0xFFDC2626),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            const SizedBox(height: 3),
                            Text(
                              chapterContent,
                              style: const TextStyle(
                                color: sphotAccessBlue,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Version SPHOT $_version',
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _acceptanceLine(
              value: accepted,
              text: acceptanceText,
              onChanged: chapters.isEmpty ? (_) {} : onChanged,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SphotAccessPage(
        title: 'RÈGLES SPHOT ADMIN',
        onBack: () => Navigator.of(context)
            .pushNamedAndRemoveUntil('/admin-request', (route) => false),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Avant toute saisie, prenez connaissance des règles '
                    'applicables à SPHOT ADMIN. Leur acceptation est '
                    'nécessaire pour commencer votre demande d’accès.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: sphotAccessBlue,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _acceptanceLine(
                    value: _representativeAccepted,
                    text:
                        'Je certifie être habilité à représenter la structure '
                        'pour laquelle je demande un accès SPHOT ADMIN.',
                    onChanged: (value) {
                      setState(
                        () => _representativeAccepted = value ?? false,
                      );
                    },
                  ),
                  _acceptanceLine(
                    value: _responsibilityAccepted,
                    text:
                        'Je reconnais que les informations renseignées dans '
                        'SPHOT sont fournies sous la responsabilité de mon '
                        'organisme, qui doit en assurer l’exactitude et la '
                        'mise à jour. Je comprends que SPHOT ne valide ni ne '
                        'certifie leur véracité ni le caractère surveillé '
                        'd’un SPHOT.',
                    onChanged: (value) {
                      setState(
                        () => _responsibilityAccepted = value ?? false,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _legalDocument(
                    title: 'Conditions Générales d’Utilisation',
                    document: _cguDocument,
                    accepted: _cguAccepted,
                    acceptanceText: 'J’ai lu et j’accepte les CGU de SPHOT.',
                    controller: _cguController,
                    onChanged: (value) {
                      setState(() => _cguAccepted = value ?? false);
                    },
                  ),
                  _legalDocument(
                    title: 'Politique de confidentialité',
                    document: _privacyDocument,
                    accepted: _privacyAccepted,
                    acceptanceText:
                        'J’ai lu et j’accepte la Politique de confidentialité '
                        'de SPHOT.',
                    controller: _privacyController,
                    onChanged: (value) {
                      setState(() => _privacyAccepted = value ?? false);
                    },
                  ),
                  _legalDocument(
                    title: 'RGPD',
                    document: _rgpdDocument,
                    accepted: _rgpdAccepted,
                    acceptanceText:
                        'J’accepte le traitement des données conformément '
                        'au RGPD.',
                    controller: _rgpdController,
                    onChanged: (value) {
                      setState(() => _rgpdAccepted = value ?? false);
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SphotAccessButton(
                    label: 'J’ACCEPTE — CONTINUER MA DEMANDE',
                    loading: _saving,
                    onPressed: _canContinue ? _acceptAndContinue : null,
                    icon: Icons.verified_user_outlined,
                  ),
                ],
              ),
      );
