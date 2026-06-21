import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class AdvertisePage extends StatefulWidget {
  const AdvertisePage({super.key});

  @override
  State<AdvertisePage> createState() => _AdvertisePageState();
}

class _AdvertisePageState extends State<AdvertisePage> {
  static const Color refColor = Color(0xFF1E3A8A);
  static const Color redRefColor = Color(0xFFDC2626);
  static const double sectionSpacing = 14;

  final _formKey = GlobalKey<FormState>();
  final stt.SpeechToText _speech = stt.SpeechToText();

  final _companyController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _websiteController = TextEditingController();
  final _messageController = TextEditingController();

  OverlayEntry? _dropdownOverlay;

  String _category = 'Protection solaire';
  final List<String> _selectedPlacements = ['Carte SPHOT'];
final List<String> _selectedTargets = ['Commune'];
  String _duration = '1 mois';
  final Set<String> _selectedOfferKeys = {
  'Carte SPHOT|Commune|1 mois',
};
  bool _isSubmitting = false;

  final List<String> _categoryChoices = [
    'Protection solaire',
    'Optique / lunettes',
    'Surfwear / prêt-à-porter',
    'Sports nautiques',
    'Tourisme',
    'Restauration',
    'Hébergement',
    'Commerce local',
    'Institutionnel',
    'Autre',
  ];

  final List<String> _placementChoices = [
    'Carte SPHOT',
    'Fiche SPHOT',
  ];

  final List<String> _targetChoices = [
    'Commune',
    'Département',
    'National',
  ];

  final List<String> _durationChoices = [
    '1 mois',
    '3 mois',
    '6 mois',
    '12 mois',
  ];

  final Map<String, Map<String, Map<String, int>>> _defaultPricing = {
    'Carte SPHOT': {
      'Commune': {
        '1 mois': 600,
        '3 mois': 1650,
        '6 mois': 3000,
        '12 mois': 5400,
      },
      'Département': {
        '1 mois': 1800,
        '3 mois': 5100,
        '6 mois': 9600,
        '12 mois': 18000,
      },
      'National': {
        '1 mois': 0,
        '3 mois': 0,
        '6 mois': 0,
        '12 mois': 0,
      },
    },
    'Fiche SPHOT': {
      'Commune': {
        '1 mois': 800,
        '3 mois': 2250,
        '6 mois': 4200,
        '12 mois': 7800,
      },
      'Département': {
        '1 mois': 2400,
        '3 mois': 6900,
        '6 mois': 13200,
        '12 mois': 25200,
      },
      'National': {
        '1 mois': 0,
        '3 mois': 0,
        '6 mois': 0,
        '12 mois': 0,
      },
    },
  };

  @override
  void dispose() {
    _companyController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _messageController.dispose();
    _dropdownOverlay?.remove();
    super.dispose();
  }

  Future<void> _startVoice(
  TextEditingController controller, {
  bool uppercase = false,
  bool contactName = false,
}) async {
    final available = await _speech.initialize();

    if (!available) return;

    await _speech.listen(
      localeId: 'fr_FR',
      onResult: (result) {
        final recognized = result.recognizedWords;

final text = contactName
    ? _formatContactName(recognized)
    : uppercase
        ? recognized.toUpperCase()
        : recognized;

        setState(() {
          controller.text = text;
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: controller.text.length),
          );
        });
      },
    );
  }

  String _storageCategory() {
    switch (_category) {
      case 'Protection solaire':
        return 'sun_care';
      case 'Optique / lunettes':
        return 'optics';
      case 'Surfwear / prêt-à-porter':
        return 'surfwear';
      case 'Sports nautiques':
        return 'watersports';
      case 'Tourisme':
        return 'tourism';
      case 'Restauration':
        return 'food';
      case 'Hébergement':
        return 'accommodation';
      case 'Commerce local':
        return 'local_business';
      case 'Institutionnel':
        return 'institutional';
      default:
        return 'other';
    }
  }

  int _durationMonths() {
    return int.tryParse(_duration.split(' ').first) ?? 1;
  }

  Map<String, Map<String, Map<String, int>>> _pricingFromFirestore(
    Map<String, dynamic>? data,
  ) {
    if (data == null || data['prices'] is! Map) {
      return _defaultPricing;
    }

    final result = <String, Map<String, Map<String, int>>>{};

    final prices = data['prices'] as Map;

    for (final placement in _placementChoices) {
      result[placement] = {};

      for (final target in _targetChoices) {
        result[placement]![target] = {};

        for (final duration in _durationChoices) {
          final value = prices[placement]?[target]?[duration];

          result[placement]![target]![duration] =
              value is num ? value.toInt() : _defaultPrice(
            placement,
            target,
            duration,
          );
        }
      }
    }

    return result;
  }

  int _defaultPrice(
    String placement,
    String target,
    String duration,
  ) {
    return _defaultPricing[placement]?[target]?[duration] ?? 0;
  }

  int _selectedPrice(
  Map<String, Map<String, Map<String, int>>> pricing,
) {
  var total = 0;

  for (final key in _selectedOfferKeys) {
    final parts = key.split('|');

    if (parts.length != 3) continue;

    final placement = parts[0];
    final target = parts[1];
    final duration = parts[2];

    total += pricing[placement]?[target]?[duration] ?? 0;
  }

  return total;
}

String _formatContactName(String value) {
  if (value.isEmpty) return value;

  final endsWithSpace = value.endsWith(' ');

  final words = value.trim().split(RegExp(r'\s+'));

  if (words.isEmpty) return value;

  final result = <String>[];

  for (int i = 0; i < words.length; i++) {
    final word = words[i];

    if (i == 0) {
      result.add(word.toUpperCase());
    } else {
      result.add(
        word
            .toLowerCase()
            .split('-')
            .map((part) {
              if (part.isEmpty) return part;

              return part[0].toUpperCase() + part.substring(1);
            })
            .join('-'),
      );
    }
  }

  var formatted = result.join(' ');

  if (endsWithSpace) {
    formatted += ' ';
  }

  return formatted;
}

  Widget _field({
    required TextEditingController controller,
    required String label,
    bool requiredField = false,
    bool uppercase = false,
    bool phone = false,
    bool contactName = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: phone ? TextInputType.phone : TextInputType.text,
      inputFormatters: phone
    ? [
        FilteringTextInputFormatter.digitsOnly,
        PhoneNumberFormatter(),
      ]
    : null,
      textCapitalization: uppercase
          ? TextCapitalization.characters
          : TextCapitalization.none,
      onChanged: (value) {
  if (contactName) {
    final formatted = _formatContactName(value);

    if (formatted != value) {
      controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(
          offset: formatted.length,
        ),
      );
    }
    return;
  }

  if (uppercase) {
    final upper = value.toUpperCase();

    if (upper != value) {
      controller.value = TextEditingValue(
        text: upper,
        selection: TextSelection.collapsed(
          offset: upper.length,
        ),
      );
    }
  }
},
      validator: requiredField
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Champ obligatoire';
              }
              return null;
            }
          : null,
      style: const TextStyle(
  color: redRefColor,
  fontWeight: FontWeight.w700,
  fontSize: 16,
),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFF1E3A8A),
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: Colors.transparent,
        suffixIcon: IconButton(
          icon: const Icon(
            Icons.mic_rounded,
            color: Color(0xFFDC2626),
          ),
          onPressed: () => _startVoice(
  controller,
  uppercase: uppercase,
  contactName: contactName,
),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 1.6),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 2),
        ),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required List<String> choices,
    required ValueChanged<String> onSelected,
    double maxMenuHeight = 220,
  }) {
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
  color: const Color(0xFFFFFFFF),
  border: const Border(
    left: BorderSide(color: Color(0xFF1E3A8A), width: 1.4),
    right: BorderSide(color: Color(0xFF1E3A8A), width: 1.4),
    bottom: BorderSide(color: Color(0xFF1E3A8A), width: 1.4),
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
                        thumbColor: MaterialStatePropertyAll(Color(0xFF1E3A8A)),
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
                            final selected = choice == value;

                            return InkWell(
                              onTap: () {
                                onSelected(choice);
                                closeMenu();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
  selected
      ? Icons.check_circle_rounded
      : Icons.circle_outlined,
  color: selected
      ? const Color(0xFFDC2626)
      : const Color(0xFF1E3A8A),
  size: 22,
),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
  choice,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(
    color: selected
        ? const Color(0xFFDC2626)
        : const Color(0xFF1E3A8A),
    fontSize: 13,
    fontWeight: FontWeight.w800,
  ),
),
                                    ),
                                  ],
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
          labelText: label,
          labelStyle: const TextStyle(
            color: Color(0xFF1E3A8A),
            fontWeight: FontWeight.w700,
          ),
          floatingLabelStyle: const TextStyle(
            color: Color(0xFF1E3A8A),
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
            borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 1.6),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 1.6),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF1E3A8A), width: 2),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
  color: Color(0xFFDC2626),
  fontSize: 16,
  fontWeight: FontWeight.w700,
),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFFDC2626),
              size: 26,
            ),
          ],
        ),
      ),
    );
  }

Widget _multiChoiceDropdownField({
  required String label,
  required List<String> selectedValues,
  required List<String> choices,
  required ValueChanged<List<String>> onChanged,
  double maxMenuHeight = 220,
}) {
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
        return StatefulBuilder(
          builder: (context, overlaySetState) {
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
                        color: Colors.white.withOpacity(0.92),
                        border: const Border(
                          left: BorderSide(color: Color(0xFFDC2626), width: 1.4),
                          right: BorderSide(color: Color(0xFFDC2626), width: 1.4),
                          bottom: BorderSide(color: Color(0xFFDC2626), width: 1.4),
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
                          thumbColor: MaterialStatePropertyAll(refColor),
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
                              final selected =
                                  selectedValues.contains(choice);

                              return InkWell(
                                onTap: () {
  final updated = [...selectedValues];

  if (selected) {
    if (updated.length > 1) {
      updated.remove(choice);
    }
  } else {
    updated.add(choice);
  }

  onChanged(updated);
  overlaySetState(() {});
},
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.check_box_rounded
                                            : Icons
                                                .check_box_outline_blank_rounded,
                                        color: const Color(0xFFDC2626),
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          choice,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFDC2626),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
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
      },
    );

    Overlay.of(context).insert(_dropdownOverlay!);
  }

  final displayText = selectedValues.join(' | ');

  return GestureDetector(
    key: fieldKey,
    onTap: openMenu,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFFDC2626),
          fontWeight: FontWeight.w700,
        ),
        floatingLabelStyle: const TextStyle(
          color: Color(0xFFDC2626),
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
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.6),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayText,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Icon(
            Icons.checklist_rounded,
            color: Color(0xFFDC2626),
            size: 24,
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFFDC2626),
            size: 26,
          ),
        ],
      ),
    ),
  );
}

String _offerKey(String placement, String target, String duration) {
  return '$placement|$target|$duration';
}

List<String> _selectedPlacementsFromOffers() {
  return _selectedOfferKeys
      .map((key) => key.split('|')[0])
      .toSet()
      .toList();
}

List<String> _selectedTargetsFromOffers() {
  return _selectedOfferKeys
      .map((key) => key.split('|')[1])
      .toSet()
      .toList();
}

List<String> _selectedDurationsFromOffers() {
  return _selectedOfferKeys
      .map((key) => key.split('|')[2])
      .toSet()
      .toList();
}

Widget _pricingTable(
  Map<String, Map<String, Map<String, int>>> pricing,
) {
  return Column(
    children: [
      const Text(
        'CHOISISSEZ VOTRE TARIF',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF1E3A8A),
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 8),
      ..._placementChoices.map((placement) {
        final title = placement == 'Carte SPHOT'
            ? 'CARTE DES SPHOTS'
            : 'FICHE DE SPHOT';

        return Container(
  width: double.infinity,
  margin: const EdgeInsets.only(bottom: sectionSpacing),
  padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0x00000000),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF1E3A8A),
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'EMPLACEMENT: ',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    TextSpan(
                      text: title,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (context, constraints) {
                  const zoneWidth = 62.0;
const cellSpacing = 6.0;

final availableWidth = constraints.maxWidth -
    zoneWidth -
    (cellSpacing * 4);

final priceWidth = (availableWidth / 4) - 2;

                  return Table(
  columnWidths: {
    0: const FixedColumnWidth(zoneWidth),
    1: FixedColumnWidth(priceWidth),
    2: FixedColumnWidth(priceWidth),
    3: FixedColumnWidth(priceWidth),
    4: FixedColumnWidth(priceWidth),
  },
  
                    defaultVerticalAlignment:
                        TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(2),
                            child: Text(
                              'Zone',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF1E3A8A),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          ..._durationChoices.map(
                            (duration) => Padding(
                              padding: const EdgeInsets.symmetric(
  horizontal: 7,
  vertical: 4,
),
                              child: Text(
                                duration.replaceAll(' mois', 'm'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF1E3A8A),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      ..._targetChoices.map((target) {
                        return TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
  horizontal: 7,
  vertical: 4,
),
                              child: Text(
                                target == 'Département'
                                    ? 'Dépt.'
                                    : target,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF1E3A8A),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            ..._durationChoices.map((duration) {
                              final price =
                                  pricing[placement]?[target]?[duration] ?? 0;

                              final key = _offerKey(placement, target, duration);
final selected = _selectedOfferKeys.contains(key);

                              return Padding(
                                padding: const EdgeInsets.symmetric(
  horizontal: 7,
  vertical: 4,
),
                                child: GestureDetector(
                                  onTap: () {
  setState(() {
    final offerKey = _offerKey(placement, target, duration);

    if (_selectedOfferKeys.contains(offerKey)) {
      if (_selectedOfferKeys.length > 1) {
        _selectedOfferKeys.remove(offerKey);
      }
    } else {
      _selectedOfferKeys.add(offerKey);
    }

    _duration = duration;
  });
},
                                  child: Container(
                                    height: 26,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? const Color(0xFFDC2626)
                                              .withOpacity(0.14)
                                          : const Color(0x00000000),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: selected
                                            ? const Color(0xFFDC2626)
                                            : const Color(0xFF1E3A8A),
                                        width: selected ? 2.1 : 1.1,
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        price == 0 ? 'DEVIS' : '$price€',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: selected
                                              ? const Color(0xFFDC2626)
                                              : const Color(0xFF1E3A8A),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      }),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      }),
    ],
  );
}  

  Widget _selectedPriceSummary(
  Map<String, Map<String, Map<String, int>>> pricing,
) {
  final price = _selectedPrice(pricing);

  final offersByPlacement = <String, List<String>>{};

  for (final key in _selectedOfferKeys) {
    final parts = key.split('|');

    if (parts.length != 3) continue;

    final placement = parts[0];
    final target = parts[1];
    final duration = parts[2];
    final offerPrice = pricing[placement]?[target]?[duration] ?? 0;

    offersByPlacement.putIfAbsent(placement, () => []);

    offersByPlacement[placement]!.add(
      offerPrice == 0
          ? 'Zone : $target\nDurée : $duration\nTarif : sur devis'
          : 'Zone : $target\nDurée : $duration\nTarif : $offerPrice € HT',
    );
  }

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: const Color(0xFF1E3A8A),
        width: 2,
      ),
    ),
    child: Column(
      children: [
        const Text(
          'RÉSUMÉ DE LA DEMANDE',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF1E3A8A),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: sectionSpacing),
        ...offersByPlacement.entries.map((entry) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: sectionSpacing),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0x00000000),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF1E3A8A),
                width: 1.4,
              ),
            ),
            child: Column(
              children: [
                Text(
                  entry.key.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ...entry.value.map((offerText) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      offerText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        }),
        
const SizedBox(height: 12),
        Text(
          price == 0 ? 'TOTAL : sur devis' : 'TOTAL : $price € HT',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFDC2626),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

  Future<void> _submit(
    Map<String, Map<String, Map<String, int>>> pricing,
  ) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    final price = _selectedPrice(pricing);

    await FirebaseFirestore.instance.collection('adRequests').add({
      'advertiserName': _companyController.text.trim(),
      'contactName': _contactController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'websiteUrl': _websiteController.text.trim(),
      'message': _messageController.text.trim(),
      'category': _storageCategory(),
      'categoryLabel': _category,
      'selectedOffers': _selectedOfferKeys.toList(),
'placementLabels': _selectedPlacementsFromOffers(),
'targetLabels': _selectedTargetsFromOffers(),
'durationLabels': _selectedDurationsFromOffers(),
      'totalPriceExclTax': price,
      'status': 'pending_review',
      'source': 'ad_banner_click',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

setState(() {
  _isSubmitting = true;
});

ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(
    content: Text('Demande publicitaire envoyée.'),
  ),
);
  }

Widget _adInfoTile({
  required BuildContext context,
  required String title,
  required String text,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: const Color(0x00000000),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: const Color(0xFF1E3A8A),
        width: 2,
      ),
    ),
    child: Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 2,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        collapsedIconColor: const Color(0xFFDC2626),
iconColor: const Color(0xFFDC2626),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF1E3A8A),
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        children: [
          Text(
            text,
            textAlign: TextAlign.justify,
            style: const TextStyle(
              color: Color(0xFF1E3A8A),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('adPricing')
          .doc('default')
          .snapshots(),
      builder: (context, snapshot) {
        final pricing = _pricingFromFirestore(snapshot.data?.data());

        return Scaffold(
  backgroundColor: const Color(0x00000000),
  body: Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'data/images/map_background.jpg',
        fit: BoxFit.cover,
      ),
      SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 58,
              child: Center(
                child: Image.asset(
                  'data/icons/title.png',
                  height: 58,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Text(
                    'DEMANDE PUBLICITAIRE',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: sectionSpacing),
                  _field(
                    controller: _companyController,
                    label: 'Entreprise / marque',
                    requiredField: true,
                    uppercase: true,                    
                  ),
                  const SizedBox(height: sectionSpacing),
                  _field(
  controller: _contactController,
  label: 'NOM Prénom du contact',
  requiredField: true,
  contactName: true,
),
                  const SizedBox(height: sectionSpacing),
                  _field(
                    controller: _emailController,
                    label: 'Email',
                    requiredField: true,
                  ),
                  const SizedBox(height: sectionSpacing),
                  _field(
                    controller: _phoneController,
                    label: 'Téléphone',
                    phone: true,
                  ),
                  const SizedBox(height: sectionSpacing),
                  _field(
                    controller: _websiteController,
                    label: 'Site internet',
                  ),
                  const SizedBox(height: sectionSpacing),
                  _dropdownField(
                    label: 'Catégorie publicitaire',
                    value: _category,
                    choices: _categoryChoices,
                    onSelected: (value) {
                      setState(() {
                        _category = value;
                      });
                    },
                  ),
                  
                  const SizedBox(height: sectionSpacing),

_adInfoTile(
  context: context,
  title: 'COMMENT FONCTIONNE LA DIFFUSION DES PUBLICITÉS ?',
  text:
      'SPHOT diffuse les publicités selon leur emplacement et leur zone géographique.\n\n'
      'Pour la carte des SPHOTS, la publicité affichée dépend du territoire consulté et du niveau de zoom.\n\n'
      'Pour la fiche d’un SPHOT, la publicité affichée dépend du SPHOT ouvert et de son territoire : commune, département, région ou pays.\n\n'
      'Les publicités locales sont prioritaires sur les campagnes plus larges.\n\n'
      'Ordre de priorité : Commune → Département → Région → National.\n\n'
      'Ainsi, les campagnes nationales ne bloquent pas les campagnes locales : elles complètent les espaces lorsqu’aucune publicité locale prioritaire n’est disponible.',
),

_adInfoTile(
  context: context,
  title: 'COMMENT SONT RÉPARTIS LES AFFICHAGES ?',
  text:
      'Lorsqu’un seul annonceur est actif sur une zone et un emplacement, sa publicité peut être affichée prioritairement sur cette zone.\n\n'
      'Lorsqu’il existe plusieurs annonceurs actifs sur une même zone, les affichages sont répartis automatiquement entre eux.\n\n'
      'Cette rotation permet à plusieurs annonceurs locaux de coexister sur une même commune, un même département ou un même emplacement.\n\n'
      'La diffusion tient compte de l’emplacement choisi, de la zone géographique, de la durée de campagne et des campagnes déjà actives.',
),

_adInfoTile(
  context: context,
  title: 'POURQUOI CHOISIR UNE DIFFUSION LOCALE ?',
  text:
      'Une campagne locale permet de toucher un public géographiquement qualifié : baigneurs, familles, touristes, pratiquants de sports nautiques ou usagers du littoral.\n\n'
      'Les campagnes communales sont les plus ciblées.\n\n'
      'Les campagnes départementales, régionales et nationales permettent d’élargir progressivement la visibilité.\n\n'
      'Le tarif varie donc selon l’emplacement choisi, la zone de diffusion et la durée de la campagne.',
),

_pricingTable(pricing),

_selectedPriceSummary(pricing),

const SizedBox(height: sectionSpacing),

_field(
  controller: _messageController,
  label: 'Message / précision',
  maxLines: 4,
),

const SizedBox(height: sectionSpacing),

SizedBox(
  width: double.infinity,
  height: 48,
  child: ElevatedButton.icon(
    onPressed: _isSubmitting ? null : () => _submit(pricing),
    icon: _isSubmitting
        ? const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFFFFFFFF),
          )
        : const Icon(
            Icons.send_rounded,
            color: Color(0xFF1E3A8A),
          ),
    label: Text(
      _isSubmitting ? 'DEMANDE ENVOYÉE' : 'ENVOYER LA DEMANDE',
      style: TextStyle(
        color: _isSubmitting
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF1E3A8A),
        fontWeight: FontWeight.w900,
      ),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: _isSubmitting
          ? const Color(0xFFDC2626)
          : const Color(0x00000000),
      disabledBackgroundColor: const Color(0xFFDC2626),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _isSubmitting
              ? const Color(0xFFDC2626)
              : const Color(0xFF1E3A8A),
          width: 2,
        ),
      ),
    ),
  ),
),
                ],
              ),
            ),
                        ),
            ),
            const SizedBox(height: sectionSpacing),
Container(
  width: 40,
  height: 40,
  margin: const EdgeInsets.only(bottom: sectionSpacing),
  decoration: BoxDecoration(
    color: const Color(0x00000000),
    shape: BoxShape.circle,
    border: Border.all(
      color: const Color(0xFF1E3A8A),
      width: 2,
    ),
  ),
  child: Material(
    color: const Color(0x00000000),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: () {
        Navigator.of(context).maybePop();
      },
      child: const Center(
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Color(0xFF1E3A8A),
          size: 22,
        ),
      ),
    ),
  ),
),
const SizedBox(height: sectionSpacing),
          ],
        ),
      ),
    ],
  ),
);
      },
    );
  }
}

class PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    final buffer = StringBuffer();

    for (var i = 0; i < digits.length && i < 10; i++) {
      if (i > 0 && i % 2 == 0) {
        buffer.write(' ');
      }
      buffer.write(digits[i]);
    }

    final text = buffer.toString();

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
