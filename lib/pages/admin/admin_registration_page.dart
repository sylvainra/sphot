import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_map_picker_page.dart';

import 'package:firebase_auth/firebase_auth.dart';



class AdminRegistrationPage extends StatefulWidget {
  const AdminRegistrationPage({super.key});

  @override
  State<AdminRegistrationPage> createState() => _AdminRegistrationPageState();
}

class _AdminRegistrationPageState extends State<AdminRegistrationPage> {
  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  final stt.SpeechToText _speech = stt.SpeechToText();

  int step = 0;
  bool _saved = false;

  OverlayEntry? _dropdownOverlay;

  final controllers = <String, TextEditingController>{};

  final List<String> structureTypes = [
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

  TextEditingController _controller(String key) {
    controllers.putIfAbsent(key, () => TextEditingController());
    return controllers[key]!;
  }

  String _value(String key) => _controller(key).text.trim();

  Future<void> _startVoice(
  TextEditingController controller, {
  bool uppercase = false,
}) async {
  final available = await _speech.initialize(
    onError: (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur micro : ${error.errorMsg}'),
          duration: const Duration(seconds: 3),
        ),
      );
    },
    onStatus: (status) {},
  );

  if (!available) {
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
      setState(() {
        controller.text = uppercase
            ? result.recognizedWords.toUpperCase()
            : result.recognizedWords;
      });
    },
  );
}

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }

    _dropdownOverlay?.remove();

    super.dispose();
  }

  Widget _stepHeader(String title, String subtitle) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: adminColor, width: 2),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: redColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: adminColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField(
  String key,
  String label, {
  bool uppercase = false,
  bool capitalizeWords = false,
  TextInputType keyboardType = TextInputType.text,
}) {
  String formatValue(String value) {
    if (uppercase) {
      return value.toUpperCase();
    }

    if (capitalizeWords) {
      return value
          .split(' ')
          .map((word) {
            if (word.isEmpty) return word;
            return word[0].toUpperCase() + word.substring(1);
          })
          .join(' ');
    }

    return value;
  }

  return TextField(
    controller: _controller(key),
    keyboardType: keyboardType,
    textCapitalization: uppercase
        ? TextCapitalization.characters
        : TextCapitalization.words,
    onChanged: (value) {
      final formatted = formatValue(value);

      if (formatted != value) {
        _controller(key).value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    },
    style: const TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 16,
      color: adminColor,
    ),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: adminColor,
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      suffixIcon: IconButton(
        icon: const Icon(
          Icons.mic_rounded,
          color: redColor,
        ),
        onPressed: () async {
          final available = await _speech.initialize();

          if (!available) return;

          await _speech.listen(
            localeId: 'fr_FR',
            listenMode: stt.ListenMode.dictation,
            onResult: (result) {
              final formatted = formatValue(result.recognizedWords);

              setState(() {
                _controller(key).text = formatted;
              });
            },
          );
        },
      ),
      fillColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: adminColor, width: 1.6),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: adminColor, width: 1.6),
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
                    child: ScrollbarTheme(
                      data: const ScrollbarThemeData(
                        thumbColor: MaterialStatePropertyAll(adminColor),
                        trackVisibility: MaterialStatePropertyAll(false),
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
                                    color: adminColor,
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: adminColor,
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

  Future<void> _openCityMapPicker() async {
    final currentLat =
        double.tryParse(_value('villeLat').replaceAll(',', '.')) ?? 0.0;
    final currentLng =
        double.tryParse(_value('villeLng').replaceAll(',', '.')) ?? 0.0;

    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => AdminMapPickerPage(
          title: 'POSITIONNEZ LA VILLE',
          initialLat: currentLat,
          initialLng: currentLng,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      _controller('villeLat').text = result.latitude.toStringAsFixed(6);
      _controller('villeLng').text = result.longitude.toStringAsFixed(6);
      _saved = false;
    });
  }

  Widget _twoColumns(Widget left, Widget right) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 8),
        Expanded(child: right),
      ],
    );
  }

  Widget _currentStep() {
    switch (step) {
      case 0:
        return Column(
          children: [
            _stepHeader(
              '1. STRUCTURE ADMINISTRATRICE',
              'Renseignez l’organisme qui utilisera SPHOT',
            ),
            _textField(
  'nomStructure',
  'Nom de la structure\nExemple : Mairie de ...',
  uppercase: true,
),
            const SizedBox(height: 8),
            _dropdownField(
              'typeStructure',
              'Type de structure',
              structureTypes,
              maxMenuHeight: 234,
            ),
          ],
        );

      case 1:
        return Column(
          children: [
            _stepHeader(
              '2. RESPONSABLE',
              'Indiquez le contact administratif référent',
            ),
            _textField(
              'nomResponsable',
              'NOM',
              uppercase: true,
            ),
            const SizedBox(height: 8),
            _textField(
  'prenomResponsable',
  'Prénom',
  capitalizeWords: true,
),
            const SizedBox(height: 8),
            _textField(
  'fonctionResponsable',
  'Fonction',
  capitalizeWords: true,
),
            const SizedBox(height: 8),
            TextField(
  controller: _controller('telephoneResponsable'),
  keyboardType: TextInputType.phone,
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
    PhoneNumberFormatter(),
  ],
  style: const TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 16,
    color: adminColor,
  ),
  decoration: InputDecoration(
    labelText: 'Téléphone',
    labelStyle: const TextStyle(
      color: adminColor,
      fontWeight: FontWeight.w700,
    ),
    filled: true,
    fillColor: Colors.transparent,
    suffixIcon: IconButton(
      icon: const Icon(
        Icons.mic_rounded,
        color: redColor,
      ),
      onPressed: () async {
        await _startVoice(
          _controller('telephoneResponsable'),
        );
      },
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 10,
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
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(
        color: adminColor,
        width: 2,
      ),
    ),
  ),
),
            const SizedBox(height: 8),
            _textField(
              'emailResponsable',
              'Email',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),

_textField(
  'adminPassword',
  'Mot de passe admin',
),

const SizedBox(height: 8),

_textField(
  'adminPasswordConfirm',
  'Confirmer le mot de passe admin',
),
          ],
        );

      case 2:
        return Column(
          children: [
            _stepHeader(
              '3. TERRITOIRE',
              'Un compte admin est rattaché à une seule ville',
            ),
            _textField(
              'pays',
              'PAYS',
              uppercase: true,
            ),
            const SizedBox(height: 8),
            _textField(
              'region',
              'RÉGION',
              uppercase: true,
            ),
            const SizedBox(height: 8),
            _textField(
              'departement',
              'DÉPARTEMENT',
              uppercase: true,
            ),
            const SizedBox(height: 8),
            _textField(
              'ville',
              'VILLE',
              uppercase: true,
            ),
          ],
        );

      default:
        return Column(
          children: [
            _stepHeader(
              '4. INFORMATIONS VILLE',
              'Ces informations prérempliront les futurs SPHOTS',
            ),
            _textField(
              'logoVille',
              'Adresse / lien du logo de la ville',
            ),
            const SizedBox(height: 8),
            _textField(
              'siteInternetVille',
              'Site internet de la ville',
            ),
            const SizedBox(height: 8),
            _textField(
              'arretesMunicipaux',
              'Adresse internet des arrêtés municipaux',
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _openCityMapPicker,
                icon: const Icon(Icons.map_outlined, color: redColor),
                label: const Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Positionnez la ville sur la carte',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: adminColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: adminColor, width: 1.6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'OU',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            _twoColumns(
  _textField(
    'villeLat',
    'Latitude\nville',
  ),
  _textField(
    'villeLng',
    'Longitude\nville',
  ),
),
          ],
        );
    }
  }

  void _nextStep() {
    if (step < 3) {
      setState(() {
        step++;
        _saved = false;
      });
    }
  }

String _territoryId() {
  String clean(String value) {
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

  return [
    clean(_value('pays')),
    clean(_value('region')),
    clean(_value('departement')),
    clean(_value('ville')),
  ].where((part) => part.isNotEmpty).join('_');
}

  Future<void> _saveRegistration() async {
  try {
    final territoryId = _territoryId();
    final email = _value('emailResponsable');
final password = _value('adminPassword');
final passwordConfirm = _value('adminPasswordConfirm');

if (email.isEmpty || password.isEmpty || passwordConfirm.isEmpty) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Renseigne l’email et le mot de passe admin.'),
      duration: Duration(seconds: 3),
    ),
  );
  return;
}

if (password != passwordConfirm) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Les mots de passe ne correspondent pas.'),
      duration: Duration(seconds: 3),
    ),
  );
  return;
}

    if (territoryId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Renseigne au minimum le pays, la région, le département et la ville.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final data = {
      'nomStructure': _value('nomStructure'),
      'typeStructure': _value('typeStructure'),
      'nomResponsable': _value('nomResponsable'),
      'prenomResponsable': _value('prenomResponsable'),
      'fonctionResponsable': _value('fonctionResponsable'),
      'telephoneResponsable': _value('telephoneResponsable'),
      'emailResponsable': _value('emailResponsable'),
      'pays': _value('pays'),
      'region': _value('region'),
      'departement': _value('departement'),
      'ville': _value('ville'),
      'logoVille': _value('logoVille'),
      'siteInternetVille': _value('siteInternetVille'),
      'arretesMunicipaux': _value('arretesMunicipaux'),
      'villeLat':
          double.tryParse(_value('villeLat').replaceAll(',', '.')) ?? 0.0,
      'villeLng':
          double.tryParse(_value('villeLng').replaceAll(',', '.')) ?? 0.0,
      'subscriptionStatus': 'TRIAL',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final docRef = FirebaseFirestore.instance
        .collection('territoires')
        .doc(territoryId);

final existingTerritory = await docRef.get();

if (existingTerritory.exists) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Ce territoire existe déjà. Vérifie le pays, la région, le département et la ville.',
      ),
      duration: Duration(seconds: 4),
    ),
  );
  return;
}

        final credential = await FirebaseAuth.instance
    .createUserWithEmailAndPassword(
  email: email,
  password: password,
);

final uid = credential.user!.uid;

    await docRef.set(
      {
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await FirebaseFirestore.instance.collection('admins').doc(uid).set({
  'uid': uid,
  'email': email,
  'territoireId': territoryId,
  'nomStructure': _value('nomStructure'),
  'typeStructure': _value('typeStructure'),
  'nomResponsable': _value('nomResponsable'),
  'prenomResponsable': _value('prenomResponsable'),
  'fonctionResponsable': _value('fonctionResponsable'),
  'telephoneResponsable': _value('telephoneResponsable'),
  'subscriptionStatus': 'TRIAL',
  'createdAt': FieldValue.serverTimestamp(),
  'updatedAt': FieldValue.serverTimestamp(),
});

    if (!mounted) return;

    setState(() {
      _saved = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Territoire enregistré : $territoryId'),
        duration: const Duration(seconds: 3),
      ),
    );
  } catch (error) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erreur enregistrement : $error'),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}

  void _previousStep() {
    if (step > 0) {
      setState(() {
        step--;
        _saved = false;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _stepControls() {
    final bool isFinalStep = step == 3;

    ButtonStyle buttonStyle({
      required Color borderColor,
      required Color foregroundColor,
      Color backgroundColor = Colors.transparent,
      Color disabledBackgroundColor = Colors.transparent,
      Color disabledForegroundColor = Colors.grey,
    }) {
      return OutlinedButton.styleFrom(
        backgroundColor: backgroundColor,
        disabledBackgroundColor: disabledBackgroundColor,
        foregroundColor: foregroundColor,
        disabledForegroundColor: disabledForegroundColor,
        side: BorderSide(
          color: borderColor,
          width: 2,
        ),
      );
    }

    TextStyle buttonTextStyle(Color color) {
      return TextStyle(
        color: color,
        fontWeight: FontWeight.w900,
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _previousStep,
            style: buttonStyle(
              borderColor: adminColor,
              foregroundColor: adminColor,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.arrow_back_rounded,
                  color: adminColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'PRÉCÉDENT',
                  style: buttonTextStyle(adminColor),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: isFinalStep
                ? (_saved ? null : _saveRegistration)
                : _nextStep,
            style: buttonStyle(
              borderColor: _saved
                  ? redColor
                  : (isFinalStep ? redColor : adminColor),
              foregroundColor: _saved
                  ? Colors.white
                  : (isFinalStep ? redColor : adminColor),
              backgroundColor:
                  _saved ? redColor : Colors.transparent,
              disabledBackgroundColor:
                  _saved ? redColor : Colors.transparent,
              disabledForegroundColor:
                  _saved ? Colors.white : Colors.grey,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isFinalStep
                        ? (_saved ? 'ENREGISTRÉ' : 'ENREGISTRER')
                        : 'SUIVANT',
                    style: buttonTextStyle(
                      _saved
                          ? Colors.white
                          : (isFinalStep ? redColor : adminColor),
                    ),
                  ),
                  if (!isFinalStep) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: adminColor,
                    ),
                  ],
                  
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'STRUCTURE',
      'RESPONSABLE',
      'TERRITOIRE',
      'VILLE',
    ];

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
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Column(
                children: [
                  Image.asset(
                    'data/icons/title.png',
                    height: 42,
                    fit: BoxFit.contain,
                  ),
                  const Text(
                    'INSCRIPTION ADMIN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: redColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
  children: List.generate(titles.length, (index) {
    final selected = index == step;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            step = index;
            _saved = false;
          });
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? redColor : adminColor,
              width: selected ? 2 : 1.2,
            ),
          ),
          child: Text(
            titles[index],
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: selected ? redColor : adminColor,
            ),
          ),
        ),
      ),
    );
  }),
),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: adminColor, width: 2),
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: _currentStep(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _stepControls(),
                ],
              ),
            ),
          ),
        ],
      ),
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