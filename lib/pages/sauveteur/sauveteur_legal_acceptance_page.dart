import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'sauveteur_access_info_page.dart';

class SauveteurLegalAcceptancePage extends StatefulWidget {
  final String login;
  final String territoireId;
  final String userRole;
  final String sphotMode;
  final String sphotModeReason;
  final String sauveteurSessionToken;
  final List<String> postesAffectes;
  final bool canManageRestrictedOperationalData;

  const SauveteurLegalAcceptancePage({
    super.key,
    required this.login,
    required this.territoireId,
    required this.userRole,
    required this.sphotMode,
    required this.sphotModeReason,
    required this.sauveteurSessionToken,
    required this.postesAffectes,
    required this.canManageRestrictedOperationalData,
  });

  @override
  State<SauveteurLegalAcceptancePage> createState() =>
      _SauveteurLegalAcceptancePageState();
}

class _SauveteurLegalAcceptancePageState
    extends State<SauveteurLegalAcceptancePage> {
  final ExpansionTileController _cguController = ExpansionTileController();
  final ExpansionTileController _privacyController =
      ExpansionTileController();
  final ExpansionTileController _rgpdController = ExpansionTileController();

  Map<String, dynamic>? _cguDocument;
  Map<String, dynamic>? _privacyDocument;
  Map<String, dynamic>? _rgpdDocument;

  String _legalVersion = '1.0';
  bool _loading = true;
  bool _submitting = false;
  String? _message;

  bool _cguAccepted = false;
  bool _privacyAcknowledged = false;
  bool _rgpdAcknowledged = false;
  bool _publicOperationalDiffusionAcknowledged = false;
  bool _institutionalReadAcknowledged = false;
  bool _personalAccountUseAccepted = false;

  bool get _canSubmit =>
      _cguAccepted &&
      _privacyAcknowledged &&
      _rgpdAcknowledged &&
      _publicOperationalDiffusionAcknowledged &&
      _institutionalReadAcknowledged &&
      _personalAccountUseAccepted &&
      !_loading &&
      !_submitting;

  @override
  void initState() {
    super.initState();
    _loadLegalPack();
  }

  Future<Map<String, dynamic>> _loadDocument(String id) async {
    final document = await FirebaseFirestore.instance
        .collection('legalDocuments')
        .doc(id)
        .get();

    final chapters = await FirebaseFirestore.instance
        .collection('legalDocuments')
        .doc(id)
        .collection('chapters')
        .orderBy(FieldPath.documentId)
        .get();

    return <String, dynamic>{
      ...?document.data(),
      'chapters': chapters.docs.map((doc) => doc.data()).toList(),
    };
  }

  Future<void> _loadLegalPack() async {
    try {
      final metadata = await FirebaseFirestore.instance
          .collection('legalDocuments')
          .doc('metadata')
          .get();

      final data = metadata.data() ?? <String, dynamic>{};

      final cgu = await _loadDocument('cgu');
      final privacy = await _loadDocument('privacyPolicy');
      final rgpd = await _loadDocument('rgpdNotice');

      if (!mounted) return;

      setState(() {
        _legalVersion = (
          data['legalVersion'] ??
          data['version'] ??
          data['activeVersion'] ??
          '1.0'
        ).toString();
        _cguDocument = cgu;
        _privacyDocument = privacy;
        _rgpdDocument = rgpd;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message =
            'Impossible de charger les documents juridiques SPHOT.';
      });
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _submitting = true;
      _message = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'acceptSauveteurLegalTerms',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sauveteurSessionToken': widget.sauveteurSessionToken,
          'legalVersion': _legalVersion,
          'cguAccepted': true,
          'privacyAcknowledged': true,
          'rgpdAcknowledged': true,
          'publicOperationalDiffusionAcknowledged': true,
          'institutionalReadAcknowledged': true,
          'personalAccountUseAccepted': true,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 409) {
        setState(() {
          _message =
              'La version juridique SPHOT a changé. '
              'Rechargez les documents avant de continuer.';
          _submitting = false;
        });
        await _loadLegalPack();
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() {
          _message =
              'La validation n’a pas pu être enregistrée. Réessayez.';
          _submitting = false;
        });
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SauveteurAccessInfoPage(
            login: widget.login,
            territoireId: widget.territoireId,
            userRole: widget.userRole,
            sphotMode: widget.sphotMode,
            sphotModeReason: widget.sphotModeReason,
            sauveteurSessionToken: widget.sauveteurSessionToken,
            postesAffectes: widget.postesAffectes,
            canManageRestrictedOperationalData:
                widget.canManageRestrictedOperationalData,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message =
            'La validation n’a pas pu être enregistrée. Réessayez.';
        _submitting = false;
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
      onChanged: _submitting ? null : onChanged,
      activeColor: const Color(0xFF1E3A8A),
      checkColor: Colors.white,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -2),
      title: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF1E3A8A),
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _legalDocument({
    required String title,
    required Map<String, dynamic>? document,
    required ExpansionTileController controller,
    required bool accepted,
    required String acceptanceText,
    required ValueChanged<bool?> onChanged,
  }) {
    final chapters = List<Map<String, dynamic>>.from(
      document?['chapters'] ?? const [],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF1E3A8A),
          width: 1.4,
        ),
      ),
      child: ExpansionTile(
        controller: controller,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1E3A8A),
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        iconColor: const Color(0xFFEF4444),
        collapsedIconColor: const Color(0xFFEF4444),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: chapters.map((chapter) {
                final title =
                    (chapter['title'] ?? chapter['titre'] ?? '').toString();
                final body =
                    (chapter['content'] ?? chapter['texte'] ?? '').toString();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title.isNotEmpty)
                        Text(
                          title,
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      if (title.isNotEmpty) const SizedBox(height: 3),
                      Text(
                        body,
                        style: const TextStyle(
                          color: Color(0xFF1F2937),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
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
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Version SPHOT $_legalVersion',
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _acceptanceLine(
              value: accepted,
              text: acceptanceText,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleCard() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF8E24AA),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RÈGLES PROFESSIONNELLES, OPÉRATIONNELLES ET DROITS DE REGARD',
            style: TextStyle(
              color: Color(0xFF8E24AA),
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'SPHOT SAUVETEUR est un outil métier opérationnel destiné '
            'aux sauveteurs exerçant une mission professionnelle de '
            'surveillance et de sécurité des zones de baignade surveillées. '
            'Ces validations encadrent son utilisation professionnelle. '
            'Elles ne rendent pas votre identité personnelle publique '
            'par défaut.',
            style: TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          _acceptanceLine(
            value: _publicOperationalDiffusionAcknowledged,
            text:
                'J’ai compris que les informations opérationnelles '
                'professionnelles que je renseigne en SPHOT ON — drapeau, '
                'statut de baignade, dangers, météo, éphéméride et données '
                'similaires — peuvent être diffusées dans SPHOT public.',
            onChanged: (value) {
              setState(() {
                _publicOperationalDiffusionAcknowledged = value ?? false;
              });
            },
          ),
          _acceptanceLine(
            value: _institutionalReadAcknowledged,
            text:
                'J’ai été informé que la MAIN COURANTE est un outil '
                'professionnel interne, non public, pouvant être consulté '
                'par l’administrateur SPHOT ADMIN et par les membres '
                'institutionnels habilités par son administration, '
                'selon leurs droits de lecture.',
            onChanged: (value) {
              setState(() {
                _institutionalReadAcknowledged = value ?? false;
              });
            },
          ),
          _acceptanceLine(
            value: _personalAccountUseAccepted,
            text:
                'Je m’engage à utiliser personnellement mes identifiants '
                'SPHOT SAUVETEUR dans le cadre de mes fonctions professionnelles, '
                'à ne pas les partager et à respecter les droits, devoirs '
                'et responsabilités associés à mon rôle.',
            onChanged: (value) {
              setState(() {
                _personalAccountUseAccepted = value ?? false;
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFEF4444);
    const blue = Color(0xFF1E3A8A);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'data/images/map_background.jpg',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
              child: Column(
                children: [
                  Image.asset(
                    'data/icons/title.png',
                    height: 54,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'VALIDATION D’ACCÈS SPHOT SAUVETEUR',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: red,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Documents juridiques SPHOT — version $_legalVersion',
                    style: const TextStyle(
                      color: blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(color: red),
                          )
                        : Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxWidth: 680),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.28),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: red, width: 2),
                            ),
                            child: ListView(
                              children: [
                                _legalDocument(
                                  title:
                                      'Conditions Générales d’Utilisation',
                                  document: _cguDocument,
                                  controller: _cguController,
                                  accepted: _cguAccepted,
                                  acceptanceText:
                                      'J’ai lu et j’accepte les CGU de SPHOT.',
                                  onChanged: (value) {
                                    setState(() {
                                      _cguAccepted = value ?? false;
                                    });
                                  },
                                ),
                                _legalDocument(
                                  title: 'Politique de confidentialité',
                                  document: _privacyDocument,
                                  controller: _privacyController,
                                  accepted: _privacyAcknowledged,
                                  acceptanceText:
                                      'J’ai pris connaissance de la '
                                      'Politique de confidentialité de SPHOT.',
                                  onChanged: (value) {
                                    setState(() {
                                      _privacyAcknowledged = value ?? false;
                                    });
                                  },
                                ),
                                _legalDocument(
                                  title: 'Notice RGPD',
                                  document: _rgpdDocument,
                                  controller: _rgpdController,
                                  accepted: _rgpdAcknowledged,
                                  acceptanceText:
                                      'J’ai pris connaissance des '
                                      'informations relatives au traitement '
                                      'de mes données et à mes droits.',
                                  onChanged: (value) {
                                    setState(() {
                                      _rgpdAcknowledged = value ?? false;
                                    });
                                  },
                                ),
                                _ruleCard(),
                                if (_message != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Text(
                                      _message!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: red,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _canSubmit ? _submit : null,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.verified_user_rounded),
                      label: Text(
                        _submitting
                            ? 'VALIDATION EN COURS…'
                            : 'VALIDER ET CONTINUER',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            const Color(0xFF94A3B8),
                        disabledForegroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
