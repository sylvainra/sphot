import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'admin_request_pending_page.dart';
import '../../web/admin/pages/dashboard_super_admin_page.dart';

class AdminTrialRequestPage extends StatefulWidget {
  final String? proConnectUid;
  final String? proConnectEmail;
  final String? proConnectNom;
  final String? proConnectPrenom;
  final String? proConnectOrganisation;
  final String? proConnectSiret;
  final String? proConnectSiren;

  const AdminTrialRequestPage({
    super.key,
    this.proConnectUid,
    this.proConnectEmail,
    this.proConnectNom,
    this.proConnectPrenom,
    this.proConnectOrganisation,
    this.proConnectSiret,
    this.proConnectSiren,
  });

  @override
  State<AdminTrialRequestPage> createState() => _AdminTrialRequestPageState();
}

enum _TrialRequestSection {
  structure,
  responsable,
  territoire,
  ville,
  essai,
}

class _TrialMapStyle {
  final String name;
  final String url;
  final List<String> subdomains;
  final int maxZoom;
  final IconData icon;

  const _TrialMapStyle({
    required this.name,
    required this.url,
    required this.icon,
    this.subdomains = const [],
    this.maxZoom = 19,
  });
}

class _AdminTrialRequestPageState extends State<AdminTrialRequestPage> {
  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  OverlayEntry? _dropdownOverlay;

  static const List<_TrialMapStyle> _mapStyles = [
    _TrialMapStyle(
      name: 'Plan',
      url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      icon: Icons.map_outlined,
      maxZoom: 19,
    ),
    _TrialMapStyle(
      name: 'Satellite',
      url:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      icon: Icons.satellite_alt_rounded,
      maxZoom: 19,
    ),
    _TrialMapStyle(
      name: 'Relief',
      url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'],
      icon: Icons.terrain_rounded,
      maxZoom: 17,
    ),
  ];

  final MapController _mapController = MapController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final Map<String, TextEditingController> _controllers = {};

  _TrialRequestSection _selectedSection = _TrialRequestSection.structure;
  int _selectedMapStyleIndex = 0;

  bool _saved = false;
  bool _isSaving = false;
  bool _certifyRepresentative = false;
  bool _acceptTerms = false;
  bool _showLegalDetails = false;
  bool _legalReadConfirmed = false;
  bool _privacyReadConfirmed = false;
  bool _rgpdAccepted = false;
  bool _legalLoading = true;

Map<String, dynamic>? _cguDoc;
Map<String, dynamic>? _privacyDoc;
Map<String, dynamic>? _rgpdDoc;

  final List<String> structureTypes = const [
    'COMMUNE',
    'COMMUNAUTÉ DE COMMUNES',
    'MÉTROPOLE',
    'DÉPARTEMENT',
    'RÉGION',
    'OFFICE DE TOURISME',
    'ASSOCIATION',
    'BASE DE LOISIRS',
    'PARC',
    'GESTIONNAIRE PRIVÉ',
    'AUTRE',
  ];

  @override
  void initState() {
    super.initState();

    _controller('nomStructure').text = widget.proConnectOrganisation ?? '';
    _controller('typeStructure').text = 'COMMUNE';
    _controller('siretStructure').text = widget.proConnectSiret ?? '';
    _controller('sirenStructure').text = widget.proConnectSiren ?? '';

    _controller('nomResponsable').text = widget.proConnectNom ?? '';
    _controller('prenomResponsable').text = widget.proConnectPrenom ?? '';
    _controller('emailResponsable').text = widget.proConnectEmail ?? '';
    _loadLegalDocuments();
  }

  @override
  void dispose() {
    _speech.stop();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _dropdownOverlay?.remove();
    super.dispose();
  }

  TextEditingController _controller(String key) {
    _controllers.putIfAbsent(key, () => TextEditingController());
    return _controllers[key]!;
  }

  String _value(String key) => _controller(key).text.trim();

  double _toDouble(String value) {
    return double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
  }

  bool get _hasCityPosition {
    return _toDouble(_value('villeLat')) != 0.0 &&
        _toDouble(_value('villeLng')) != 0.0;
  }

  bool get _structureComplete {
    return _value('nomStructure').isNotEmpty &&
        _value('typeStructure').isNotEmpty;
  }

  bool get _responsableComplete {
    return _value('nomResponsable').isNotEmpty &&
        _value('prenomResponsable').isNotEmpty &&
        _value('fonctionResponsable').isNotEmpty &&
        _value('emailResponsable').isNotEmpty;
  }

  bool get _territoireComplete {
    return _value('pays').isNotEmpty &&
        _value('region').isNotEmpty &&
        _value('departement').isNotEmpty &&
        _value('ville').isNotEmpty;
  }

  bool get _villeComplete {
  return _value('logoVille').isNotEmpty &&
      _value('siteInternetVille').isNotEmpty &&
      _value('arretesMunicipaux').isNotEmpty &&
      _hasCityPosition;
}

  bool get _canOpenTrialRequest {
    return _structureComplete &&
        _responsableComplete &&
        _territoireComplete &&
        _villeComplete;
  }

  bool get _canSubmitTrialRequest {
  return _canOpenTrialRequest &&
      _certifyRepresentative &&
      _legalReadConfirmed &&
      _privacyReadConfirmed &&
      _rgpdAccepted;
}

  String _normalizeIdPart(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâäãå]'), 'a')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[òóôöõ]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ýÿ]'), 'y')
        .replaceAll('æ', 'ae')
        .replaceAll('œ', 'oe')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _territoryId() {
    return [
      _normalizeIdPart(_value('pays')),
      _normalizeIdPart(_value('region')),
      _normalizeIdPart(_value('departement')),
      _normalizeIdPart(_value('ville')),
    ].where((part) => part.isNotEmpty).join('_');
  }

  String _capitalizeWords(String value) {
    return value.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String _formatText(
    String value, {
    bool uppercase = false,
    bool capitalizeWords = false,
  }) {
    if (uppercase) return value.toUpperCase();
    if (capitalizeWords) return _capitalizeWords(value);
    return value;
  }

  void _selectSection(_TrialRequestSection section) {
    if (section == _TrialRequestSection.essai && !_canOpenTrialRequest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complétez Structure, Responsable, Territoire et Ville avant la demande d’essai.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _selectedSection = section;
      _saved = false;
    });
  }

  Future<void> _startVoice(
    String key, {
    bool uppercase = false,
    bool capitalizeWords = false,
  }) async {
    final available = await _speech.initialize(
      onError: (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur micro : ${error.errorMsg}'),
            duration: const Duration(seconds: 3),
          ),
        );
      },
    );

    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reconnaissance vocale non disponible ou micro non autorisé.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    await _speech.listen(
      localeId: 'fr_FR',
      listenMode: stt.ListenMode.dictation,
      onResult: (result) {
        final formatted = _formatText(
          result.recognizedWords.trim(),
          uppercase: uppercase,
          capitalizeWords: capitalizeWords,
        );

        setState(() {
          _controller(key).text = formatted;
          _saved = false;
        });
      },
    );
  }

  void _setCityPosition(LatLng point) {
    setState(() {
      _controller('villeLat').text = point.latitude.toStringAsFixed(6);
      _controller('villeLng').text = point.longitude.toStringAsFixed(6);
      _saved = false;
    });

    _mapController.move(point, 12);
  }

  void _centerOnCity() {
    if (!_hasCityPosition) return;

    _mapController.move(
      LatLng(
        _toDouble(_value('villeLat')),
        _toDouble(_value('villeLng')),
      ),
      12,
    );
  }

Future<void> _loadLegalDocuments() async {
  try {
    final firestore = FirebaseFirestore.instance;

    final cgu = await firestore.collection('legalDocuments').doc('cgu').get();
    final privacy =
        await firestore.collection('legalDocuments').doc('privacyPolicy').get();
    final rgpd =
        await firestore.collection('legalDocuments').doc('rgpdNotice').get();

    if (!mounted) return;

    setState(() {
      _cguDoc = cgu.data();
      _privacyDoc = privacy.data();
      _rgpdDoc = rgpd.data();
      _legalLoading = false;
    });
  } catch (error) {
    if (!mounted) return;

    setState(() {
      _legalLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erreur chargement documents légaux : $error'),
      ),
    );
  }
}

  Future<void> _saveRegistration() async {
    if (_isSaving || _saved || !_canSubmitTrialRequest) return;

    setState(() => _isSaving = true);

    try {
      final territoryId = _territoryId();
      final user = FirebaseAuth.instance.currentUser;
      final uid = widget.proConnectUid ?? user?.uid;

      if (uid == null || uid.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connexion ProConnect introuvable.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('adminRequests')
          .doc(uid)
          .set({
        'uid': uid,

        'proConnect': {
          'uid': widget.proConnectUid,
          'email': widget.proConnectEmail,
          'nom': widget.proConnectNom,
          'prenom': widget.proConnectPrenom,
          'organisation': widget.proConnectOrganisation,
          'siret': widget.proConnectSiret,
          'siren': widget.proConnectSiren,
        },

        'profile': {
          'nomAffiche': _value('nomResponsable'),
          'prenomAffiche': _value('prenomResponsable'),
          'fonction': _value('fonctionResponsable'),
          'telephone': _value('telephoneResponsable'),
          'email': _value('emailResponsable'),
        },

        'structure': {
          'nom': _value('nomStructure'),
          'type': _value('typeStructure'),
          'siret': _value('siretStructure'),
          'siren': _value('sirenStructure'),
        },

        'territoire': {
          'territoireId': territoryId,
          'pays': _value('pays'),
          'region': _value('region'),
          'departement': _value('departement'),
          'ville': _value('ville'),
          'logoVille': _value('logoVille'),
          'siteInternetVille': _value('siteInternetVille'),
          'arretesMunicipaux': _value('arretesMunicipaux'),
          'villeLat': _toDouble(_value('villeLat')),
          'villeLng': _toDouble(_value('villeLng')),
        },

        'trialRequest': {
  'trialDurationDays': 8,
  'certifyRepresentative': _certifyRepresentative,
  'legalReadConfirmed': _legalReadConfirmed,
  'privacyReadConfirmed': _privacyReadConfirmed,
  'rgpdAccepted': _rgpdAccepted,
  'acceptedLegalDocuments': {
    'cguVersion': (_cguDoc?['version'] ?? '1.0').toString(),
'privacyVersion': (_privacyDoc?['version'] ?? '1.0').toString(),
'rgpdVersion': (_rgpdDoc?['version'] ?? '1.0').toString(),
    'acceptedAt': FieldValue.serverTimestamp(),
  },
  'commercialLabel': 'Demande d’essai gratuit SPHOT',
},

        'subscriptionPreview': {
          'trialDurationDays': 8,
          'pricePerStationExclTax': 500,
          'billingCycle': 'annual',
          'vatRate': 20,
          'status': 'awaiting_validation',
        },

        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _saved = true;
        _isSaving = false;
      });

      Navigator.of(context).pushReplacement(
  MaterialPageRoute(
    builder: (_) => const DashboardSuperAdminPage(),
  ),
);
    } catch (error) {
      if (!mounted) return;

      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur enregistrement : $error'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Widget _textField(
    String key,
    String label, {
    bool uppercase = false,
    bool capitalizeWords = false,
    bool readOnly = false,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: _controller(key),
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization:
          uppercase ? TextCapitalization.characters : TextCapitalization.words,
      onChanged: (value) {
        final formatted = _formatText(
          value,
          uppercase: uppercase,
          capitalizeWords: capitalizeWords,
        );

        if (formatted != value) {
          _controller(key).value = TextEditingValue(
            text: formatted,
            selection: TextSelection.collapsed(offset: formatted.length),
          );
        }

        setState(() => _saved = false);
      },
      style: const TextStyle(
        color: adminColor,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: adminColor,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: Colors.transparent,
        suffixIcon: readOnly
            ? const Icon(Icons.lock_outline_rounded, color: adminColor)
            : IconButton(
                icon: const Icon(Icons.mic_rounded, color: redColor),
                onPressed: () => _startVoice(
                  key,
                  uppercase: uppercase,
                  capitalizeWords: capitalizeWords,
                ),
              ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: adminColor, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: adminColor, width: 2),
        ),
      ),
    );
  }

  Widget _dropdownField(
  String key,
  String label,
  List<String> choices, {
  double maxMenuHeight = 220,
}) {
  final current = _value(key);
  final fieldKey = GlobalKey();

  void closeMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  void openMenu() {
    closeMenu();

    final renderBox =
        fieldKey.currentContext!.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final scrollController = ScrollController();

    _dropdownOverlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: closeMenu,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: position.dx,
              top: position.dy + size.height - 10,
              width: size.width,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: BoxConstraints(maxHeight: maxMenuHeight),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.88),
                    border: const Border(
                      left: BorderSide(color: adminColor, width: 1.4),
                      right: BorderSide(color: adminColor, width: 1.4),
                      bottom: BorderSide(color: adminColor, width: 1.4),
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Scrollbar(
                    controller: scrollController,
                    thumbVisibility: true,
                    thickness: 10,
                    radius: const Radius.circular(10),
                    child: ListView.builder(
                      controller: scrollController,
                      primary: false,
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: choices.length,
                      itemBuilder: (context, index) {
                        final choice = choices[index];

                        return InkWell(
                          onTap: () {
                            setState(() {
                              _controller(key).text = choice;
                              _saved = false;
                            });
                            closeMenu();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Text(
                              choice,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: redColor,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_dropdownOverlay!);
  }

  return GestureDetector(
    key: fieldKey,
    onTap: openMenu,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: current.isEmpty ? null : label,
        labelStyle: const TextStyle(
          color: adminColor,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: adminColor,
            width: 1.6,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: adminColor,
            width: 1.6,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              current.isEmpty ? label : current,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: current.isEmpty ? adminColor : redColor,
              ),
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: redColor,
            size: 26,
          ),
        ],
      ),
    ),
  );
}

  Widget _certifiedBlock() {
    final hasCertifiedData =
        widget.proConnectEmail != null ||
        widget.proConnectNom != null ||
        widget.proConnectPrenom != null ||
        widget.proConnectOrganisation != null ||
        widget.proConnectSiret != null ||
        widget.proConnectSiren != null;

    if (!hasCertifiedData) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: adminColor.withOpacity(0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: adminColor.withOpacity(0.35),
          width: 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user_rounded, color: redColor, size: 20),
              SizedBox(width: 8),
              Text(
                'IDENTITÉ CERTIFIÉE PROCONNECT',
                style: TextStyle(
                  color: redColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _smallInfo('Nom', widget.proConnectNom),
          _smallInfo('Prénom', widget.proConnectPrenom),
          _smallInfo('Email', widget.proConnectEmail),
          _smallInfo('Organisation', widget.proConnectOrganisation),
          _smallInfo('SIRET', widget.proConnectSiret),
          _smallInfo('SIREN', widget.proConnectSiren),
        ],
      ),
    );
  }

  Widget _smallInfo(String label, String? value) {
    final display = (value == null || value.isEmpty) ? 'Non renseigné' : value;

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              '$label :',
              style: const TextStyle(
                color: adminColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              display,
              style: const TextStyle(
                color: adminColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageHeader(String title, String subtitle) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: adminColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: adminColor, width: 1.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: redColor,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: adminColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _leftMenu() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.97),
        border: Border(
          right: BorderSide(
            color: adminColor.withOpacity(0.25),
            width: 1.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
const Text(
  'ADMIN',
  textAlign: TextAlign.center,
  style: TextStyle(
    color: redColor,
    fontSize: 18,
    fontWeight: FontWeight.w900,
  ),
),
const SizedBox(height: 24),
              _menuButton(
                section: _TrialRequestSection.structure,
                icon: Icons.account_balance_rounded,
                label: 'STRUCTURE',
                completed: _structureComplete,
              ),
              _menuButton(
                section: _TrialRequestSection.responsable,
                icon: Icons.person_rounded,
                label: 'RESPONSABLE',
                completed: _responsableComplete,
              ),
              _menuButton(
                section: _TrialRequestSection.territoire,
                icon: Icons.public_rounded,
                label: 'TERRITOIRE',
                completed: _territoireComplete,
              ),
              _menuButton(
                section: _TrialRequestSection.ville,
                icon: Icons.place_rounded,
                label: 'LIEU',
                completed: _villeComplete,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  color: adminColor.withOpacity(0.55),
                  thickness: 1,
                ),
              ),
              _menuButton(
                section: _TrialRequestSection.essai,
                icon: Icons.rocket_launch_rounded,
                label: 'DEMANDE D’ESSAI',
                completed: _canSubmitTrialRequest,
                enabled: _canOpenTrialRequest,
              ),
              const Spacer(),
              _statusCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuButton({
    required _TrialRequestSection section,
    required IconData icon,
    required String label,
    required bool completed,
    bool enabled = true,
  }) {
    final selected = _selectedSection == section;
    final effectiveColor =
        !enabled ? Colors.grey : (selected ? redColor : adminColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedButton(
        onPressed: enabled ? () => _selectSection(section) : null,
        style: OutlinedButton.styleFrom(
          elevation: 0,
          backgroundColor:
              selected ? effectiveColor.withOpacity(0.08) : Colors.transparent,
          foregroundColor: effectiveColor,
          disabledForegroundColor: Colors.grey,
          side: BorderSide(
            color: effectiveColor,
            width: selected ? 2 : 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 15,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Icon(
              completed
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    final text = _canOpenTrialRequest
        ? 'Dossier complet.\nVous pouvez demander votre essai gratuit.'
        : 'Complétez les étapes pour débloquer la demande d’essai.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (_canOpenTrialRequest ? adminColor : Colors.grey).withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _canOpenTrialRequest ? adminColor : Colors.grey,
          width: 1.4,
        ),
      ),
      child: Column(
        children: [
          Icon(
            _canOpenTrialRequest
                ? Icons.lock_open_rounded
                : Icons.lock_outline_rounded,
            color: _canOpenTrialRequest ? adminColor : Colors.grey.shade700,
            size: 26,
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _canOpenTrialRequest ? adminColor : Colors.grey.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapCenter() {
    final style = _mapStyles[_selectedMapStyleIndex];

    final cityLat = _toDouble(_value('villeLat'));
    final cityLng = _toDouble(_value('villeLng'));

    final cityPoint = _hasCityPosition
        ? LatLng(cityLat, cityLng)
        : const LatLng(20, 0);

    return Expanded(
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: cityPoint,
              initialZoom: _hasCityPosition ? 11 : 2.2,
              minZoom: 2,
              maxZoom: style.maxZoom.toDouble(),
              onTap: (tapPosition, point) {
                if (_selectedSection != _TrialRequestSection.ville) return;
                _setCityPosition(point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: style.url,
                subdomains: style.subdomains,
                maxZoom: style.maxZoom.toDouble(),
                userAgentPackageName: 'com.sphot.app',
              ),
              if (_hasCityPosition)
                MarkerLayer(
                  markers: [
                    Marker(
  point: cityPoint,
  width: 62,
  height: 62,
  alignment: Alignment.topCenter,
  child: Image.asset(
    'data/icons/fire_red_icon.png',
    filterQuality: FilterQuality.high,
  ),
),
                  ],
                ),
            ],
          ),
          Positioned(
  top: 14,
  left: 0,
  right: 0,
  child: Center(
    child: Image.asset(
      'data/icons/title.png',
      height: 48,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    ),
  ),
),
          _mapTopBanner(),
          _mapStyleControls(),
        ],
      ),
    );
  }

  Widget _mapTopBanner() {
    final isVille = _selectedSection == _TrialRequestSection.ville;

    return Positioned(
      top: 76,
      left: 18,
      right: 18,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: Colors.black.withOpacity(0.26),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isVille ? Icons.place_rounded : Icons.public_rounded,
              color: isVille ? redColor : adminColor,
              size: 23,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isVille
                    ? 'Cliquez sur la carte pour positionner le lieu.'
                    : 'Carte SPHOT — utilisez l’étape Lieu pour placer le territoire.',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isVille ? redColor : adminColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapStyleControls() {
    final style = _mapStyles[_selectedMapStyleIndex];

    return Positioned(
      right: 16,
      bottom: 22,
      child: Column(
        children: [
          FloatingActionButton.small(
            heroTag: 'trial-map-style',
            backgroundColor: Colors.white,
            foregroundColor: adminColor,
            onPressed: () {
              setState(() {
                _selectedMapStyleIndex =
                    (_selectedMapStyleIndex + 1) % _mapStyles.length;
              });
            },
            child: Icon(style.icon),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'trial-map-recenter',
            backgroundColor: Colors.white,
            foregroundColor: adminColor,
            onPressed: () {
              if (_hasCityPosition) {
                _centerOnCity();
              } else {
                _mapController.move(const LatLng(20, 0), 2.2);
              }
            },
            child: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
    );
  }

  Widget _rightPanel() {
    return Container(
      width: 450,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.985),
        border: Border(
          left: BorderSide(
            color: adminColor.withOpacity(0.25),
            width: 1.5,
          ),
        ),
      ),
      child: SafeArea(
  child: Align(
    alignment: Alignment.topCenter,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: _selectedPanel(),
    ),
  ),
),
    );
  }

  Widget _selectedPanel() {
    switch (_selectedSection) {
      case _TrialRequestSection.structure:
        return _structurePanel();
      case _TrialRequestSection.responsable:
        return _responsablePanel();
      case _TrialRequestSection.territoire:
        return _territoirePanel();
      case _TrialRequestSection.ville:
        return _villePanel();
      case _TrialRequestSection.essai:
        return _trialRequestPanel();
    }
  }

  Widget _structurePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeader(
          'STRUCTURE',
          'Renseignez l’organisme qui utilisera SPHOT.',
        ),
        _textField(
          'nomStructure',
          'Nom de la structure',
          uppercase: true,
          readOnly: widget.proConnectOrganisation != null,
        ),
        const SizedBox(height: 11),
        _dropdownField(
          'typeStructure',
          'Type de structure',
          structureTypes,
        ),
        const SizedBox(height: 11),
        _textField(
          'siretStructure',
          'SIRET',
          keyboardType: TextInputType.number,
          readOnly: widget.proConnectSiret != null,
        ),
        const SizedBox(height: 11),
_textField(
  'sirenStructure',
  'SIREN',
  keyboardType: TextInputType.number,
  readOnly: widget.proConnectSiren != null,
),
        const SizedBox(height: 22),
        _nextButton(_TrialRequestSection.responsable),
      ],
    );
  }

  Widget _responsablePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeader(
          'RESPONSABLE',
          'Identité du référent admin SPHOT.',
        ),
        _certifiedBlock(),
        _textField(
          'nomResponsable',
          'Nom',
          uppercase: true,
        ),
        const SizedBox(height: 11),
        _textField(
          'prenomResponsable',
          'Prénom',
          capitalizeWords: true,
        ),
        const SizedBox(height: 11),
        _textField(
          'fonctionResponsable',
          'Fonction',
          capitalizeWords: true,
        ),
        const SizedBox(height: 11),
        _textField(
          'telephoneResponsable',
          'Téléphone',
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            PhoneNumberFormatter(),
          ],
        ),
        const SizedBox(height: 11),
        _textField(
          'emailResponsable',
          'Email de contact',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 22),

const SizedBox(height: 22),

Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    _previousButton(_TrialRequestSection.structure), // adapter selon la page

    const SizedBox(width: 20),

    _nextButton(_TrialRequestSection.territoire), // adapter selon la page
  ],
),
      ],
    );
  }

  Widget _territoirePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeader(
          'TERRITOIRE',
          'Un accès admin SPHOT est rattaché à une ville.',
        ),
        _textField('pays', 'Pays', uppercase: true),
        const SizedBox(height: 11),
        _textField('region', 'Région', uppercase: true),
        const SizedBox(height: 11),
        _textField('departement', 'Département', uppercase: true),
        const SizedBox(height: 11),
        _textField('ville', 'Ville', uppercase: true),
        const SizedBox(height: 22),
const SizedBox(height: 22),

Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    _previousButton(_TrialRequestSection.responsable), // adapter selon la page

    const SizedBox(width: 20),

    _nextButton(_TrialRequestSection.ville), // adapter selon la page
  ],
),
      ],
    );
  }

  Widget _villePanel() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _pageHeader(
        'LIEU',
        'Positionnez le lieu sur la carte centrale.',
      ),
      _textField(
        'logoVille',
        'Adresse / lien du logo du lieu',
      ),
      const SizedBox(height: 11),
      _textField(
        'siteInternetVille',
        'Site internet du lieu',
      ),
      const SizedBox(height: 11),
      _textField(
        'arretesMunicipaux',
        'Adresse internet des arrêtés municipaux',
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: adminColor.withOpacity(0.055),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: adminColor.withOpacity(0.3),
          ),
        ),
        child: const Text(
          'Astuce : cliquez directement sur la carte pour enregistrer les coordonnées du lieu.',
          style: TextStyle(
            color: adminColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _hasCityPosition ? _centerOnCity : null,
          icon: const Icon(Icons.center_focus_strong_rounded),
          label: const Text(
            'CENTRER SUR LE LIEU',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: adminColor,
            disabledForegroundColor: Colors.grey,
            side: BorderSide(
              color: _hasCityPosition ? adminColor : Colors.grey,
              width: 1.6,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: _textField(
              'villeLat',
              'Latitude',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _textField(
              'villeLng',
              'Longitude',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Center(
        child: _previousButton(_TrialRequestSection.territoire),
      ),
    ],
  );
}

  Widget _trialRequestPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeader(
          'DEMANDE D’ESSAI SPHOT',
          'Découvrez gratuitement SPHOT pendant 8 jours.',
        ),
        const Text(
  'Découvrez les services de SPHOT :',
  style: TextStyle(
    color: adminColor,
    fontSize: 16,
    fontWeight: FontWeight.w800,
    height: 1.3,
  ),
),
const SizedBox(height: 18),
        _trialFeature(
  'Centralisez la gestion de vos SPHOTS et de vos sauveteurs',
),

_trialFeature(
  'Valorisez vos SPHOTS auprès du public',
),

_trialFeature(
  'Analysez la fréquentation de vos SPHOTS',
),

_trialFeature(
  'Informez en temps réel sur les conditions de baignade',
),

_trialFeature(
  'Partagez les conditions météo et maritimes',
),

_trialFeature(
  'Diffusez la couleur du drapeau et les dangers du jour',
),
        
        const SizedBox(height: 18),
        _trialSummaryCard(),
        const SizedBox(height: 16),
        _checkLine(
  value: _certifyRepresentative,
  text: 'Je certifie être habilité à représenter cette structure.',
  onChanged: (value) {
    setState(() {
      _certifyRepresentative = value ?? false;
      _saved = false;
    });
  },
),

ListTile(
  contentPadding: EdgeInsets.zero,
  title: const Text(
    'Conditions Générales, confidentialité et RGPD',
    style: TextStyle(
      color: adminColor,
      fontSize: 13,
      fontWeight: FontWeight.w900,
    ),
  ),
  trailing: Icon(
    _showLegalDetails
        ? Icons.keyboard_arrow_up_rounded
        : Icons.keyboard_arrow_down_rounded,
    color: redColor,
  ),
  onTap: () {
    setState(() {
      _showLegalDetails = !_showLegalDetails;
    });
  },
),

if (_showLegalDetails) ...[
  Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: adminColor.withOpacity(0.045),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: adminColor.withOpacity(0.35),
        width: 1.2,
      ),
    ),
    child: _legalLoading
    ? const Center(
        child: CircularProgressIndicator(),
      )
    : Text(
        [
          (_cguDoc?['content'] ??
                  'Conditions Générales d’Utilisation SPHOT à compléter.')
              .toString(),
          '',
          (_privacyDoc?['content'] ??
                  'Politique de confidentialité SPHOT à compléter.')
              .toString(),
          '',
          (_rgpdDoc?['content'] ??
                  'Notice RGPD SPHOT à compléter.')
              .toString(),
        ].join('\n\n'),
        style: const TextStyle(
          color: adminColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
  ),
  const SizedBox(height: 10),
  _checkLine(
    value: _legalReadConfirmed,
    text: 'J’ai lu et j’accepte les Conditions Générales d’Utilisation de SPHOT.',
    onChanged: (value) {
      setState(() {
        _legalReadConfirmed = value ?? false;
        _saved = false;
      });
    },
  ),
  _checkLine(
    value: _privacyReadConfirmed,
    text: 'J’ai pris connaissance de la Politique de confidentialité de SPHOT.',
    onChanged: (value) {
      setState(() {
        _privacyReadConfirmed = value ?? false;
        _saved = false;
      });
    },
  ),
  _checkLine(
    value: _rgpdAccepted,
    text: 'J’accepte le traitement des données nécessaires conformément au RGPD.',
    onChanged: (value) {
      setState(() {
        _rgpdAccepted = value ?? false;
        _saved = false;
      });
    },
  ),
],
        const SizedBox(height: 18),
        
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _canSubmitTrialRequest && !_isSaving
                ? _saveRegistration
                : null,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.rocket_launch_rounded),
            label: Text(
              _isSaving
                  ? 'ENVOI EN COURS'
                  : (_saved
                      ? 'DEMANDE ENVOYÉE'
                      : 'DEMANDER MON ESSAI GRATUIT'),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: adminColor,
              disabledBackgroundColor: Colors.grey.shade400,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _trialFeature(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: adminColor,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: adminColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trialSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: redColor.withOpacity(0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: redColor.withOpacity(0.55),
          width: 1.3,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Essai gratuit de 8 jours',
            style: TextStyle(
              color: redColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Sans engagement. Aucune facturation avant validation.',
            style: TextStyle(
              color: adminColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkLine({
    required bool value,
    required String text,
    required ValueChanged<bool?> onChanged,
  }) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      activeColor: adminColor,
      checkColor: Colors.white,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Text(
        text,
        style: const TextStyle(
          color: adminColor,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
    );
  }

  Widget _nextButton(
  _TrialRequestSection nextSection, {
  bool enabled = true,
}) {
  return SizedBox(
    width: 180,
    height: 48,
    child: OutlinedButton(
      onPressed: enabled ? () => _selectSection(nextSection) : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: adminColor,
        disabledForegroundColor: Colors.grey,
        side: BorderSide(
          color: enabled ? adminColor : Colors.grey,
          width: 1.6,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'SUIVANT',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SizedBox(width: 8),
          Icon(Icons.arrow_forward_rounded),
        ],
      ),
    ),
  );
}

  Widget _desktopLayout() {
    return Row(
      children: [
        _leftMenu(),
        _mapCenter(),
        _rightPanel(),
      ],
    );
  }

  Widget _mobileLayout() {
    return Column(
      children: [
        SizedBox(
          height: 360,
          child: _mapCenter(),
        ),
        Expanded(
          child: Row(
            children: [
              _leftMenu(),
              _rightPanel(),
            ],
          ),
        ),
      ],
    );
  }

Widget _previousButton(_TrialRequestSection previousSection) {
  return SizedBox(
    width: 180,
    height: 48,
    child: OutlinedButton(
      onPressed: () => _selectSection(previousSection),
      style: OutlinedButton.styleFrom(
        foregroundColor: adminColor,
        side: const BorderSide(
          color: adminColor,
          width: 1.6,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.arrow_back_rounded),
          SizedBox(width: 8),
          Text(
            'PRÉCÉDENT',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      body: width < 1000 ? _mobileLayout() : _desktopLayout(),
    );
  }
}

class PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }

    final buffer = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 2 == 0) {
        buffer.write(' ');
      }
      buffer.write(digits[i]);
    }

    final formatted = buffer.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
