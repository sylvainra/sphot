import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';


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
OverlayEntry? _dropdownOverlay;
TextEditingController? _activeVoiceController;

final _companyController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _websiteController = TextEditingController();
  final _centerCityController = TextEditingController();
  final _messageController = TextEditingController();
  final _sirenController = TextEditingController();
  final _siretController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

Uint8List? _bannerBytes;
String? _bannerFileName;
String? _bannerFileExtension;
String? _bannerMimeType;
int? _bannerFileSizeBytes;

  String _category = '';
  String _visibility = 'pack';
  String _broadcastType = 'local';
  String _duration = '15 jours';
  DateTime _campaignStartDate = DateTime.now();

DateTime get _campaignEndDate {
  switch (_duration) {
    case '15 jours':
      return _campaignStartDate.add(const Duration(days: 15));

    case '1 mois':
      return DateTime(
        _campaignStartDate.year,
        _campaignStartDate.month + 1,
        _campaignStartDate.day,
      );

    case '3 mois':
      return DateTime(
        _campaignStartDate.year,
        _campaignStartDate.month + 3,
        _campaignStartDate.day,
      );

    case '6 mois':
      return DateTime(
        _campaignStartDate.year,
        _campaignStartDate.month + 6,
        _campaignStartDate.day,
      );

    case '12 mois':
      return DateTime(
        _campaignStartDate.year + 1,
        _campaignStartDate.month,
        _campaignStartDate.day,
      );
  }

  return _campaignStartDate;
}
  double _radiusKm = 0.5;
  bool _isSubmitting = false;

  LatLng _adCenter = const LatLng(46.6, 2.5);

  final MapController _adMapController = MapController();
  bool _searchingPlace = false;

  LatLng get _circleCenter {
  return LatLng(
    _adCenter.latitude - 0.000002,
    _adCenter.longitude,
  );
}

  LatLng get _circleVisualCenter {
  final zoom = _adMapController.camera.zoom;

  final metersPerPixel =
      156543.03392 *
      cos(_adCenter.latitude * pi / 180) /
      pow(2, zoom);

  final metersNorth = 30 * metersPerPixel;

  return LatLng(
    _adCenter.latitude + (metersNorth / 111320),
    _adCenter.longitude,
  );
}

  final List<String> _categoryChoices = [
  'Cosmétique',
  'Optique / lunettes',
  'Surfwear / prêt-à-porter',
  'Sports nautiques',
  'Tourisme',
  'Restauration',
  'Produits alimentaires',
  'Boissons',
  'Hôtellerie',
  'Hôtellerie de plein air',
  'Commerce local',
  'Institutionnel',
  'Autre',
];

  final List<String> _durationChoices = [
    '15 jours',
    '1 mois',
    '3 mois',
    '6 mois',
    '12 mois',
  ];

  final List<double> _radiusChoices = [0.5, 2, 5, 10, 20, 50, 100];

  @override
  void dispose() {
    _companyController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _centerCityController.dispose();
    _messageController.dispose();
    _dropdownOverlay?.remove();
    _speech.stop();
    _speech.cancel();
    _sirenController.dispose();
    _siretController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _defaultPricing() {
    return {
      'basePrices': {
        '15 jours': 99,
        '1 mois': 149,
        '3 mois': 349,
        '6 mois': 599,
        '12 mois': 999,
      },
      'visibilityMultipliers': {
        'map': 1.0,
        'premium': 2.0,
        'pack': 2.5,
      },
      'radiusMultipliers': {
  '0.5': 1.0,
  '2': 1.5,
  '5': 2.0,
  '10': 2.8,
  '20': 3.8,
  '50': 5.5,
  '100': 8.0,
},
      'nationalFlatPrices': {
        'map': {
          '15 jours': 490,
          '1 mois': 790,
          '3 mois': 1900,
          '6 mois': 2900,
          '12 mois': 4900,
        },
        'premium': {
          '15 jours': 890,
          '1 mois': 1490,
          '3 mois': 3400,
          '6 mois': 5400,
          '12 mois': 8900,
        },
        'pack': {
          '15 jours': 1190,
          '1 mois': 1990,
          '3 mois': 4500,
          '6 mois': 7400,
          '12 mois': 11900,
        },
      },
    };
  }

  num _numFromMap(Map map, String key, num fallback) {
    final value = map[key];
    return value is num ? value : fallback;
  }

  int _campaignPrice(Map<String, dynamic>? firestorePricing) {
    final pricing = firestorePricing ?? _defaultPricing();

    if (_broadcastType == 'national') {
      final national = pricing['nationalFlatPrices'];
      if (national is Map &&
          national[_visibility] is Map &&
          national[_visibility][_duration] is num) {
        return (national[_visibility][_duration] as num).round();
      }

      final fallback = _defaultPricing()['nationalFlatPrices'][_visibility]
          [_duration] as int;
      return fallback;
    }

    final basePrices = pricing['basePrices'] is Map
        ? pricing['basePrices'] as Map
        : _defaultPricing()['basePrices'] as Map;

    final visibilityMultipliers = pricing['visibilityMultipliers'] is Map
        ? pricing['visibilityMultipliers'] as Map
        : _defaultPricing()['visibilityMultipliers'] as Map;

    final radiusMultipliers = pricing['radiusMultipliers'] is Map
        ? pricing['radiusMultipliers'] as Map
        : _defaultPricing()['radiusMultipliers'] as Map;

    final base = _numFromMap(basePrices, _duration, 99);
    final visibility = _numFromMap(visibilityMultipliers, _visibility, 2.5);
    final radius = _numFromMap(radiusMultipliers, _radiusKm.toString(), 1.0);

    return (base * visibility * radius).round();
  }

  String _visibilityLabel() {
    switch (_visibility) {
      case 'map':
        return 'Carte SPHOT';
      case 'premium':
        return 'SPHOT';
      default:
        return 'Pack Visibilité Totale';
    }
  }

  String _storageCategory() {
  switch (_category) {
    case 'Cosmétique':
      return 'cosmetics';

    case 'Optique / lunettes':
      return 'optics';

    case 'Surfwear / prêt-à-porter':
      return 'surfwear';

    case 'Sports nautiques':
      return 'watersports';

    case 'Tourisme':
      return 'tourism';

    case 'Restauration':
      return 'restaurant';

    case 'Produits alimentaires':
      return 'food_products';

    case 'Boissons':
      return 'beverages';

    case 'Hôtellerie':
      return 'hotel';

    case 'Hôtellerie de plein air':
      return 'camping';

    case 'Commerce local':
      return 'local_business';

    case 'Institutionnel':
      return 'institutional';

    default:
      return 'other';
  }
}

Future<void> _pickBannerImage() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);

  if (picked == null) return;

  final bytes = await picked.readAsBytes();

  setState(() {
    _bannerBytes = bytes;
  });
}

void _openBannerPreview() {
  if (_bannerBytes == null) return;

  showDialog(
    context: context,
    builder: (_) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image.memory(
            _bannerBytes!,
            fit: BoxFit.contain,
          ),
        ),
      );
    },
  );
}

Future<void> _searchReferencePlace() async {
  final query = _centerCityController.text.trim();

  if (query.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Merci de saisir une commune ou un lieu.'),
      ),
    );
    return;
  }

  setState(() {
    _searchingPlace = true;
  });

  try {
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      {
        'q': query,
        'format': 'json',
        'limit': '1',
        'countrycodes': 'fr',
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': 'SPHOT advertising configurator',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Erreur géocodage');
    }

    final results = jsonDecode(response.body) as List<dynamic>;

    if (results.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lieu introuvable. Essayez avec une commune proche.'),
        ),
      );
      return;
    }

    final result = results.first as Map<String, dynamic>;

    final lat = double.tryParse(result['lat'].toString());
    final lon = double.tryParse(result['lon'].toString());

    if (lat == null || lon == null) {
      throw Exception('Coordonnées invalides');
    }

    final newCenter = LatLng(lat, lon);

    setState(() {
      _adCenter = newCenter;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  _adMapController.move(newCenter, 12);
});
  } catch (e) {
  debugPrint('ERREUR LOCALISATION : $e');
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Impossible de localiser ce lieu pour le moment.'),
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        _searchingPlace = false;
      });
    }
  }
}

  Future<void> _startVoice(
  TextEditingController controller, {
  bool uppercase = false,
  bool contactName = false,
}) async {
  try {
    await _speech.stop();
    await _speech.cancel();
  } catch (_) {}

  _activeVoiceController = controller;

  final available = await _speech.initialize();

  if (!available) return;

  await _speech.listen(
    localeId: 'fr_FR',
    listenMode: stt.ListenMode.dictation,
    partialResults: true,
    onResult: (result) {
      if (_activeVoiceController != controller) {
        return;
      }

      final recognized = result.recognizedWords.trim();

      final text = contactName
          ? _formatContactName(recognized)
          : uppercase
              ? recognized.toUpperCase()
              : recognized;

      if (!mounted) return;

      setState(() {
        controller.text = text;
        controller.selection = TextSelection.collapsed(
          offset: text.length,
        );
      });
    },
  );
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
      textCapitalization:
          uppercase ? TextCapitalization.characters : TextCapitalization.none,
      onChanged: (value) {
        if (contactName) {
          final formatted = _formatContactName(value);

          if (formatted != value) {
            controller.value = TextEditingValue(
              text: formatted,
              selection: TextSelection.collapsed(offset: formatted.length),
            );
          }
          return;
        }

        if (uppercase) {
          final upper = value.toUpperCase();

          if (upper != value) {
            controller.value = TextEditingValue(
              text: upper,
              selection: TextSelection.collapsed(offset: upper.length),
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
    color: refColor,
    fontWeight: FontWeight.w700,
  ),

  errorStyle: const TextStyle(
    color: redRefColor,
    fontWeight: FontWeight.w700,
  ),
        filled: true,
        fillColor: Colors.transparent,
        suffixIcon: IconButton(
  icon: const Icon(
    Icons.mic_rounded,
    color: redRefColor,
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
          borderSide: const BorderSide(color: refColor, width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: refColor, width: 1.6),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: refColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
  borderRadius: BorderRadius.circular(14),
  borderSide: const BorderSide(
    color: redRefColor,
    width: 2,
  ),
),

focusedErrorBorder: OutlineInputBorder(
  borderRadius: BorderRadius.circular(14),
  borderSide: const BorderSide(
    color: redRefColor,
    width: 2.5,
  ),
),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: refColor,
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _choiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? redRefColor : refColor,
            width: selected ? 2.4 : 1.7,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? redRefColor : refColor,
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (badge != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: redRefColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? redRefColor : refColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: refColor,
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              color: selected ? redRefColor : refColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _visibilitySelector() {
  return Column(
    children: [
      _sectionTitle('CHOISISSEZ VOTRE VISIBILITÉ'),
      const SizedBox(height: 10),

      Row(
        children: [
          Expanded(
            child: _visualVisibilityCard(
              title: 'Carte SPHOTS',
              subtitle: 'Visible lors de la navigation sur la carte principale.',
              icon: Icons.map_rounded,
              selected: _visibility == 'map',
              onTap: () => setState(() => _visibility = 'map'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _visualVisibilityCard(
  title: 'SPHOT',
  subtitle: 'Visible directement sur la fiche détaillée d’un SPHOT.',
  iconAsset: _visibility == 'premium'
      ? 'data/icons/fire_red_icon.png'
      : 'data/icons/fire_blue_icon.png',
  selected: _visibility == 'premium',
  onTap: () => setState(() => _visibility = 'premium'),
),
          ),
        ],
      ),

      const SizedBox(height: 12),

      _packVisibilityCard(),
    ],
  );
}

Widget _visualVisibilityCard({
  required String title,
  required String subtitle,
  IconData? icon,
String? iconAsset,
  required bool selected,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? redRefColor : refColor,
          width: selected ? 2.4 : 1.7,
        ),
      ),
      child: Column(
        children: [
          _phoneMockup(),
          const SizedBox(height: 10),
          iconAsset != null
    ? Image.asset(
        iconAsset,
        width: 34,
        height: 34,
        fit: BoxFit.contain,
      )
    : Icon(
        icon,
        color: selected ? redRefColor : refColor,
        size: 30,
      ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? redRefColor : refColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: refColor,
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? redRefColor : refColor,
            size: 28,
          ),
        ],
      ),
    ),
  );
}

Widget _packVisibilityCard() {
  final selected = _visibility == 'pack';

  return GestureDetector(
    onTap: () => setState(() => _visibility = 'pack'),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: redRefColor,
          width: selected ? 2.8 : 2,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: redRefColor,
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Text(
              'RECOMMANDÉ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _phoneMockup()),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  children: [
                    const Icon(
                      Icons.stars_rounded,
                      color: redRefColor,
                      size: 34,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pack Visibilité Totale',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected ? redRefColor : refColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Présence simultanée sur la carte et les fiches SPHOTS.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: refColor,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _packBullet('Maximisez votre visibilité'),
                    _packBullet('Touchez plus d’utilisateurs'),
                    _packBullet('Le meilleur impact'),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _phoneMockup()),
            ],
          ),
          const SizedBox(height: 10),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: redRefColor,
            size: 30,
          ),
        ],
      ),
    ),
  );
}

Widget _packBullet(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      children: [
        const Icon(
          Icons.check_circle_rounded,
          color: redRefColor,
          size: 18,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: refColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _phoneMockup() {
  final screenWidth = MediaQuery.of(context).size.width;
  final bool compactWeb = kIsWeb && screenWidth > 700;

  final phone = Center(
    child: SizedBox(
      width: compactWeb ? 92 : null,
      child: AspectRatio(
        aspectRatio: 0.58,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'data/images/map_background.jpg',
                  fit: BoxFit.cover,
                ),
                Container(color: Colors.white.withOpacity(0.10)),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Image.asset(
                      'data/icons/title.png',
                      height: compactWeb ? 16 : 22,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: compactWeb ? 26 : 38,
                  child: _PhoneBannerPreview(
                    bannerBytes: _bannerBytes,
                    compactWeb: compactWeb,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  return _PhoneMockupZoom(
    enabled: _bannerBytes != null,
    child: phone,
  );
}

Widget _bannerUploadSection() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: refColor, width: 2),
    ),
    child: Column(
      children: [
        _sectionTitle('VISUEL PUBLICITAIRE'),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pickBannerImage,
          icon: const Icon(
            Icons.upload_file_rounded,
            color: redRefColor,
          ),
          label: Text(
            _bannerFileName == null
                ? 'TÉLÉVERSER VOTRE VISUEL'
                : _bannerFileName!,
            style: const TextStyle(
              color: redRefColor,
              fontWeight: FontWeight.w900,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: refColor, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Format recommandé : 1200 x 600 px • PNG, JPG ou WEBP • 5 Mo max',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: refColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

  Widget _broadcastSelector() {
  return Column(
    children: [
      _sectionTitle('CHOISISSEZ VOTRE DIFFUSION'),
      const SizedBox(height: 10),
      _choiceCard(
        title: 'Diffusion locale',
        subtitle:
            'Positionnez votre SPHOT publicitaire ci-dessous et définissez son rayon d’action.',
        icon: Icons.radar_rounded,
        selected: _broadcastType == 'local',
        onTap: () => setState(() => _broadcastType = 'local'),
      ),
      _choiceCard(
        title: 'Diffusion nationale',
        subtitle: 'Diffusez sur l’ensemble des SPHOTS nationaux.',
        icon: Icons.public_rounded,
        badge: 'NATIONAL',
        selected: _broadcastType == 'national',
        onTap: () => setState(() => _broadcastType = 'national'),
      ),
    ],
  );
}

  Widget _visualMapSimulator() {
  return Column(
    children: [
      _sectionTitle('POSITIONNEZ VOTRE SPHOT PUBLICITAIRE'),
      const SizedBox(height: 8),

      Row(
        children: [
          Expanded(
            child: _field(
  controller: _centerCityController,
  label: 'SPHOT de référence (optionnel)',
  requiredField: false,
  uppercase: true,
),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            width: 48,
            child: OutlinedButton(
              onPressed: _searchingPlace ? null : _searchReferencePlace,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: const BorderSide(color: refColor, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _searchingPlace
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.search_rounded,
                      color: redRefColor,
                      size: 28,
                    ),
            ),
          ),
        ],
      ),

      const SizedBox(height: 12),

      const Text(
        'Déplacez la carte, zoomez, puis cliquez pour positionner votre SPHOT publicitaire.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: refColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),

      const SizedBox(height: 12),

      Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.82,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: refColor, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 1.65,
                child: FlutterMap(
                  mapController: _adMapController,
                  options: MapOptions(
                    initialCenter: _adCenter,
                    initialZoom: 6,
                    minZoom: 4,
                    maxZoom: 18,
                    onTap: (tapPosition, point) {
                      setState(() {
                        _adCenter = point;
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.bathing_spots_app',
                    ),
                    CircleLayer(
                      circles: [
                        CircleMarker(
  point: _circleCenter,
  radius: _radiusKm == 0 ? 1 : _radiusKm * 1000,
  useRadiusInMeter: true,
  color: redRefColor.withOpacity(0.12),
  borderColor: redRefColor,
  borderStrokeWidth: 2,
),
                      ],
                    ),
                    MarkerLayer(
  markers: [
    Marker(
  point: _adCenter,
  width: 60,
  height: 60,
  alignment: Alignment.center,
  child: Transform.translate(
    offset: const Offset(0, -28),
    child: Image.asset(
      'data/icons/fire_red_icon.png',
      fit: BoxFit.contain,
    ),
  ),
),
  ],
),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),

      const SizedBox(height: 12),

      _radiusSelector(),
    ],
  );
}

  Widget _radiusSelector() {
  return Column(
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: _radiusChoices.map((radius) {
          final selected = _radiusKm == radius;

          return OutlinedButton(
            onPressed: () => setState(() => _radiusKm = radius),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: selected ? redRefColor : refColor,
              side: BorderSide(
                color: selected ? redRefColor : refColor,
                width: selected ? 2.2 : 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            child: Text(
              '$radius km',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
     
    ],
  );
}

  Widget _durationSelector() {
  String formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  return Column(
    children: [
      _sectionTitle('CHOISISSEZ VOTRE DURÉE'),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: _durationChoices.map((duration) {
          final selected = _duration == duration;

          return OutlinedButton(
            onPressed: () => setState(() => _duration = duration),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: selected ? redRefColor : refColor,
              side: BorderSide(
                color: selected ? redRefColor : refColor,
                width: selected ? 2.2 : 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              duration.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
      SizedBox(
  width: 240,
  height: 42,
  child: OutlinedButton.icon(
    onPressed: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: _campaignStartDate,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 730)),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: redRefColor,
                onPrimary: Colors.white,
                onSurface: refColor,
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        setState(() {
          _campaignStartDate = picked;
        });
      }
    },
    icon: const Icon(
      Icons.calendar_month_rounded,
      color: redRefColor,
    ),
    label: Text(
      'Début : ${formatDate(_campaignStartDate)}',
      style: const TextStyle(
        color: redRefColor,
        fontWeight: FontWeight.w900,
      ),
    ),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(
        color: refColor,
        width: 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  ),
),
      const SizedBox(height: 10),
      SizedBox(
  width: 240,
  height: 42,
  child: OutlinedButton(
    onPressed: null,
    style: OutlinedButton.styleFrom(
      disabledForegroundColor: redRefColor,
      side: const BorderSide(
        color: refColor,
        width: 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    child: Text(
      'Fin : ${formatDate(_campaignEndDate)}',
      style: const TextStyle(
        color: redRefColor,
        fontWeight: FontWeight.w900,
      ),
    ),
  ),
),
    ],
  );
}

  Widget _categorySelector() {
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
                  constraints: const BoxConstraints(maxHeight: 240),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    border: const Border(
                      left: BorderSide(color: refColor, width: 1.4),
                      right: BorderSide(color: refColor, width: 1.4),
                      bottom: BorderSide(color: refColor, width: 1.4),
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
                        itemCount: _categoryChoices.length,
                        itemBuilder: (context, index) {
                          final choice = _categoryChoices[index];
                          final selected = choice == _category;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _category = choice;
                              });
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
                                    color: selected ? redRefColor : refColor,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      choice,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? redRefColor
                                            : refColor,
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
        labelText: 'Catégorie publicitaire',
        labelStyle: const TextStyle(
          color: refColor,
          fontWeight: FontWeight.w700,
        ),
        floatingLabelStyle: const TextStyle(
          color: refColor,
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
          borderSide: const BorderSide(color: refColor, width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: refColor, width: 1.6),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: refColor, width: 2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
  _category.isEmpty ? 'Catégorie publicitaire' : _category,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(
    color: _category.isEmpty ? refColor : redRefColor,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  ),
),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: redRefColor,
            size: 26,
          ),
        ],
      ),
    ),
  );
}

  Widget _summary(Map<String, dynamic>? pricing) {
    final price = _campaignPrice(pricing);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: redRefColor,
          width: 2.3,
        ),
      ),
      child: Column(
        children: [
          const Text(
            'RÉSUMÉ DE VOTRE CAMPAGNE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: refColor,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _summaryLine(Icons.visibility_rounded, _visibilityLabel()),
          _summaryLine(
            _broadcastType == 'national'
                ? Icons.public_rounded
                : Icons.location_on_rounded,
            _broadcastType == 'national'
                ? 'Diffusion nationale'
                : '${_centerCityController.text.trim().isEmpty ? 'Épicentre à renseigner' : _centerCityController.text.trim()} • Rayon $_radiusKm km',
          ),
          _summaryLine(Icons.calendar_month_rounded, _duration),
          _summaryLine(Icons.category_rounded, _category),
          const SizedBox(height: 14),
          Text(
            '$price € HT',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: redRefColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tarif estimatif soumis à validation SPHOT.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: refColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, color: redRefColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: refColor,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
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
          color: refColor,
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
          collapsedIconColor: redRefColor,
          iconColor: redRefColor,
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: refColor,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          children: [
            Text(
              text,
              textAlign: TextAlign.justify,
              style: const TextStyle(
                color: refColor,
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

  Future<void> _submit(Map<String, dynamic>? pricing) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final price = _campaignPrice(pricing);

    await FirebaseFirestore.instance.collection('adRequests').add({
      'advertiserName': _companyController.text.trim(),
      'contactName': _contactController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'websiteUrl': _websiteController.text.trim(),
      'message': _messageController.text.trim(),
      'category': _storageCategory(),
      'categoryLabel': _category,
      'visibilityType': _visibility,
      'visibilityLabel': _visibilityLabel(),
      'broadcastType': _broadcastType,
      'centerCity': _broadcastType == 'local'
          ? _centerCityController.text.trim()
          : '',
      'centerLat': _broadcastType == 'local' ? _adCenter.latitude : null,
      'centerLng': _broadcastType == 'local' ? _adCenter.longitude : null,
      'radiusKm': _broadcastType == 'local' ? _radiusKm : null,
      'durationLabel': _duration,
      'campaignStartDate': Timestamp.fromDate(
  _campaignStartDate,
),

'campaignEndDate': Timestamp.fromDate(
  _campaignEndDate,
),
      'totalPriceExclTax': price,
      'status': 'pending_review',
      'source': 'advertiser_portal',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'siren': _sirenController.text.trim(),
      'siret': _siretController.text.trim(),
    });

    if (!mounted) return;

    setState(() => _isSubmitting = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demande publicitaire envoyée.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('advertisingPricing')
          .snapshots(),
      builder: (context, snapshot) {
        final pricing = snapshot.data?.data();

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
                                'FAITES RAYONNER VOTRE ACTIVITÉ !',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: redRefColor,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: sectionSpacing),
                              _adInfoTile(
                                context: context,
                                title: 'COMMENT FONCTIONNE LA DIFFUSION ?',
                                text:
                                    'Choisissez votre visibilité : Carte SPHOT, Fiche SPHOT Premium ou Pack Visibilité Totale.\n\n'
                                    'Pour une campagne locale, vous positionnez un épicentre et choisissez un rayon d’action. Votre publicité pourra être diffusée sur les SPHOTS situés dans ce rayon.\n\n'
                                    'Pour une campagne nationale, aucun épicentre n’est nécessaire : votre publicité peut apparaître sur l’ensemble des SPHOTS.',
                              ),
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

_bannerUploadSection(),

const SizedBox(height: sectionSpacing),

_field(
  controller: _sirenController,
  label: 'SIREN issu de ProConnect',
  requiredField: true,
),

const SizedBox(height: sectionSpacing),

_field(
  controller: _siretController,
  label: 'SIRET issu de ProConnect',
  requiredField: true,
),
                              const SizedBox(height: sectionSpacing),
                              _categorySelector(),
                              const SizedBox(height: sectionSpacing),
                              _visibilitySelector(),
                              const SizedBox(height: sectionSpacing),
                              _broadcastSelector(),

const SizedBox(height: 4),

AnimatedSwitcher(
  duration: const Duration(milliseconds: 180),
  child: _broadcastType == 'local'
      ? _visualMapSimulator()
      : const SizedBox.shrink(),
),

const SizedBox(height: 2),

_durationSelector(),
                              const SizedBox(height: sectionSpacing),
                              _summary(pricing),
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
                                  onPressed: _isSubmitting
                                      ? null
                                      : () => _submit(pricing),
                                  icon: _isSubmitting
                                      ? const Icon(
                                          Icons.check_circle_rounded,
                                          color: Colors.white,
                                        )
                                      : const Icon(
                                          Icons.send_rounded,
                                          color: refColor,
                                        ),
                                  label: Text(
                                    _isSubmitting
                                        ? 'DEMANDE ENVOYÉE'
                                        : 'ENVOYER LA DEMANDE',
                                    style: TextStyle(
                                      color: _isSubmitting
                                          ? Colors.white
                                          : refColor,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isSubmitting
                                        ? redRefColor
                                        : Colors.transparent,
                                    disabledBackgroundColor: redRefColor,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: BorderSide(
                                        color: _isSubmitting
                                            ? redRefColor
                                            : refColor,
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
                          color: refColor,
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
                              color: refColor,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
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

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF1E3A8A).withOpacity(0.28)
      ..strokeWidth = 1;

    final roadPaint = Paint()
      ..color = const Color(0xFFDC2626).withOpacity(0.26)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    for (var i = 1; i < 6; i++) {
      final dx = size.width * i / 6;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), linePaint);
    }

    for (var i = 1; i < 4; i++) {
      final dy = size.height * i / 4;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), linePaint);
    }

    final path = Path()
      ..moveTo(0, size.height * 0.75)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.35,
        size.width,
        size.height * 0.55,
      );

    canvas.drawPath(path, roadPaint);

    final coastPaint = Paint()
      ..color = const Color(0xFF1E3A8A).withOpacity(0.34)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    final coast = Path()
      ..moveTo(0, size.height * 0.20)
      ..quadraticBezierTo(
        size.width * 0.40,
        size.height * 0.05,
        size.width,
        size.height * 0.18,
      );

    canvas.drawPath(coast, coastPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

class _PhoneBannerPreview extends StatelessWidget {
  final Uint8List? bannerBytes;
  final bool compactWeb;

  const _PhoneBannerPreview({
    required this.bannerBytes,
    required this.compactWeb,
  });

  @override
  Widget build(BuildContext context) {
    if (bannerBytes == null) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.72),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'PUBLICITÉ LOCALE\nCamping • Surf Shop • Restaurant',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _AdvertisePageState.refColor,
            fontSize: compactWeb ? 6 : 8,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 2,
        child: Image.memory(
          bannerBytes!,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _PhoneMockupZoom extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const _PhoneMockupZoom({
    required this.child,
    required this.enabled,
  });

  @override
  State<_PhoneMockupZoom> createState() => _PhoneMockupZoomState();
}

class _PhoneMockupZoomState extends State<_PhoneMockupZoom> {
  OverlayEntry? _hoverOverlay;

  void _showHoverZoom() {
    if (!kIsWeb || !widget.enabled || _hoverOverlay != null) return;

    _hoverOverlay = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: Colors.black.withOpacity(0.18),
              child: Center(
                child: Transform.scale(
                  scale: 2.8,
                  child: widget.child,
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_hoverOverlay!);
  }

  void _hideHoverZoom() {
    _hoverOverlay?.remove();
    _hoverOverlay = null;
  }

  void _openPhoneZoom() {
    if (!widget.enabled) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.72),
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(4),
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 10,
            child: Center(
              child: SizedBox(
                width: 650,
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _hideHoverZoom();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
  return Center(
    child: MouseRegion(
      onEnter: (_) => _showHoverZoom(),
      onExit: (_) => _hideHoverZoom(),
      child: GestureDetector(
        onTap: _openPhoneZoom,
        child: IntrinsicWidth(
          child: widget.child,
        ),
      ),
    ),
  );
}
}