import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../shared/web_colors.dart';

class AdvertiserLegalAcceptanceSection extends StatefulWidget {
  const AdvertiserLegalAcceptanceSection({
    super.key,
    required this.requestId,
    required this.requestStatus,
    this.onSubmitted,
  });

  final String? requestId;
  final String requestStatus;
  final VoidCallback? onSubmitted;

  @override
  State<AdvertiserLegalAcceptanceSection> createState() =>
      _AdvertiserLegalAcceptanceSectionState();
}

class _AdvertiserLegalAcceptanceSectionState
    extends State<AdvertiserLegalAcceptanceSection> {
  final ExpansionTileController _cguController = ExpansionTileController();
  final ExpansionTileController _privacyController = ExpansionTileController();
  final ExpansionTileController _rgpdController = ExpansionTileController();

  Map<String, dynamic>? _cguDocument;
  Map<String, dynamic>? _privacyDocument;
  Map<String, dynamic>? _rgpdDocument;

  bool _loading = true;
  bool _submitting = false;
  bool _applicationCompleted = false;
  bool _cguAccepted = false;
  bool _privacyAccepted = false;
  bool _rgpdAccepted = false;
  String _version = '1.0';
  String? _error;
  String? _success;

  bool get _locked {
    final status = widget.requestStatus.toLowerCase();
    return status == 'pending' || status == 'approved';
  }

  bool get _canSubmit =>
      _applicationCompleted &&
      _cguAccepted &&
      _privacyAccepted &&
      _rgpdAccepted &&
      !_locked &&
      !_submitting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> _map(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : {};
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

  Future<void> _load() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final requestId = widget.requestId?.trim() ?? '';

      final metadata =
          await firestore.collection('legalDocuments').doc('metadata').get();
      final cgu = await _loadLegalDocument('cgu');
      final privacy = await _loadLegalDocument('privacyPolicy');
      final rgpd = await _loadLegalDocument('rgpdNotice');

      Map<String, dynamic> request = {};
      if (requestId.isNotEmpty) {
        final snapshot = await firestore
            .collection('advertiserRequests')
            .doc(requestId)
            .get();
        request = snapshot.data() ?? <String, dynamic>{};
      }

      final acceptedDocuments = _map(request['acceptedDocuments']);

      if (!mounted) return;
      setState(() {
        _version = (metadata.data()?['version'] ?? '1.0').toString();
        _cguDocument = cgu;
        _privacyDocument = privacy;
        _rgpdDocument = rgpd;
        _applicationCompleted = request['applicationCompleted'] == true;
        _cguAccepted = acceptedDocuments['cgu'] == true;
        _privacyAccepted = acceptedDocuments['privacy'] == true;
        _rgpdAccepted = acceptedDocuments['rgpd'] == true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les documents juridiques.';
      });
      debugPrint('Chargement documents juridiques annonceur impossible : $error');
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final requestId = widget.requestId?.trim() ?? '';
    if (requestId.isEmpty) {
      setState(() {
        _error = 'Identifiez-vous avant de transmettre la demande.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _success = null;
    });

    try {
      final reference = FirebaseFirestore.instance
          .collection('advertiserRequests')
          .doc(requestId);
      final snapshot = await reference.get();
      final data = snapshot.data() ?? <String, dynamic>{};

      if (data['profileCompleted'] != true ||
          data['establishmentCompleted'] != true ||
          data['applicationCompleted'] != true) {
        throw const _LegalSubmissionException(
          'Terminez les deux premières étapes avant la transmission.',
        );
      }

      final recipient =
          (data['contactEmail'] ?? data['email'] ?? '').toString().trim();

      await reference.set({
        'status': 'pending',
        'legalAcceptanceCompleted': true,
        'acceptedDocuments': <String, Object?>{
          'cgu': true,
          'privacy': true,
          'rgpd': true,
          'version': _version,
          'acceptedAt': FieldValue.serverTimestamp(),
        },
        'acknowledgementEmail': <String, Object?>{
          'status': 'pending',
          'recipient': recipient,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'review': <String, Object?>{
          'status': 'pending',
          'reason': '',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _cguController.collapse();
      _privacyController.collapse();
      _rgpdController.collapse();
      setState(() {
        _submitting = false;
        _success = 'Votre demande a été transmise à l’équipe SPHOT.';
      });
      widget.onSubmitted?.call();
    } on _LegalSubmissionException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'La transmission a échoué. Réessayez.';
      });
      debugPrint('Transmission juridique annonceur impossible : $error');
    }
  }

  Widget _acceptanceLine({
    required bool value,
    required String text,
    required ValueChanged<bool?> onChanged,
  }) {
    return CheckboxListTile(
      value: value,
      onChanged: _locked ? null : onChanged,
      activeColor: WebColors.blue,
      checkColor: Colors.white,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      horizontalTitleGap: 0,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -2),
      title: Text(
        text,
        style: const TextStyle(
          color: WebColors.blue,
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
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WebColors.blue, width: 1.4),
      ),
      child: ExpansionTile(
        controller: controller,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        title: Text(
          title,
          style: const TextStyle(
            color: WebColors.blue,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        iconColor: WebColors.red,
        collapsedIconColor: WebColors.red,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: chapters.isEmpty
                  ? const [
                      Text(
                        'Aucun chapitre renseigné.',
                        style: TextStyle(
                          color: WebColors.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ]
                  : chapters.map((chapter) {
                      final chapterTitle =
                          (chapter['title'] ?? chapter['titre'] ?? '').toString();
                      final chapterContent =
                          (chapter['content'] ?? chapter['texte'] ?? '')
                              .toString();

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (chapterTitle.isNotEmpty)
                              Text(
                                chapterTitle,
                                style: const TextStyle(
                                  color: WebColors.red,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              chapterContent,
                              style: const TextStyle(
                                color: WebColors.blue,
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
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Version SPHOT $_version',
                style: const TextStyle(
                  color: WebColors.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          _acceptanceLine(
            value: accepted,
            text: acceptanceText,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: WebColors.red),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Consultez puis acceptez les documents applicables avant de '
          'transmettre votre demande de SPHOT PUBLICITAIRE.',
          style: TextStyle(
            color: WebColors.blue,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 18),
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
              'J’ai lu et j’accepte la Politique de confidentialité de SPHOT.',
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
              'J’accepte le traitement des données conformément au RGPD.',
          controller: _rgpdController,
          onChanged: (value) {
            setState(() => _rgpdAccepted = value ?? false);
          },
        ),
        if (!_applicationCompleted && !_locked)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Terminez et enregistrez d’abord les deux premières étapes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebColors.red,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WebColors.red,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        if (_success != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _success!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF15803D),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _canSubmit ? _submit : null,
            style: FilledButton.styleFrom(
              backgroundColor: WebColors.blue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _locked
                  ? WebColors.red
                  : const Color(0xFF94A3B8),
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    _locked
                        ? Icons.check_circle_outline_rounded
                        : Icons.send_rounded,
                  ),
            label: Text(
              _submitting
                  ? 'ENVOI EN COURS…'
                  : _locked
                      ? 'DEMANDE TRANSMISE'
                      : 'TRANSMETTRE LA DEMANDE',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegalSubmissionException implements Exception {
  const _LegalSubmissionException(this.message);

  final String message;
}
