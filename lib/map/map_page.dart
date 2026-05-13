import 'dart:math';
import 'dart:ui' as ui;
import 'dart:async';
import 'lifeguard_login_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/flag_state.dart';
import '../services/firestore_service.dart';
import 'flag_marker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'app_info_page.dart';

enum SpotFilter {
  all,
  secours,
  accesPlage,
  eauBleue,
  eauVerte,
  lagon,
  naturisme,
  autre,
}

class _MapTileStyle {
  final String name;
  final String url;
  final List<String> subdomains;
  final int maxZoom;

  const _MapTileStyle({
    required this.name,
    required this.url,
    this.subdomains = const [],
    this.maxZoom = 19,
  });
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FirestoreService _firestoreService = FirestoreService();
  final MapController _mapController = MapController();

  SpotFilter _selectedFilter = SpotFilter.all;

  double _currentRotation = 0;
  int _selectedTileStyle = 0;
  int _selectedBottomIndex = 1;
  bool _isMovingMap = false;
  Timer? _mapMoveTimer;
Timer? _searchTimer;

bool _isFilterOpen = false;
bool _isMapStyleOpen = false;

final TextEditingController _searchController = TextEditingController();
final FocusNode _searchFocusNode = FocusNode();

late stt.SpeechToText _speech;
bool _isListening = false;

static const List<_MapTileStyle> _tileStyles = [
  _MapTileStyle(
    name: 'Plan',
    url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    maxZoom: 19,
  ),
  _MapTileStyle(
  name: 'Satellite',
  url:
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  maxZoom: 19,
  ),
  _MapTileStyle(
    name: 'Relief',
    url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
    maxZoom: 17,
  ),
];

@override
void initState() {
  super.initState();
  _speech = stt.SpeechToText();
}

  bool _showFlagForZoom(double zoom) => zoom >= 12.5;

  bool _showTextForZoom(double zoom) {
    final isTouchDevice =
        Theme.of(context).platform == TargetPlatform.android ||
            Theme.of(context).platform == TargetPlatform.iOS;

    if (isTouchDevice) {
      return zoom >= 16.0;
    }

    return zoom >= 13.0;
  }

  double _labelOpacity(double zoom) {
    if (zoom >= 14.5) return 1.0;
    if (zoom >= 13.8) return 0.88;
    if (zoom >= 13.0) return 0.72;
    return 0.0;
  }

  List<Marker> _buildTerritoryLogoMarkers(double zoom, double rotation) {
    final markers = <Marker>[];

    if (zoom >= 9 && zoom < 12) {
      markers.add(
        Marker(
          point: const LatLng(46.6706076, -1.4266839),
          width: 80,
          height: 80,
          child: Transform.rotate(
            angle: -rotation * pi / 180,
            child: Image.asset(
              'data/logos_departements/france/pays_de_la_loire/vendee.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    if (zoom >= 12) {
      markers.add(
        Marker(
          point: const LatLng(46.4239682, -1.4897203),
          width: 70,
          height: 70,
          child: Transform.rotate(
            angle: -rotation * pi / 180,
            child: Image.asset(
              'data/logos_communes/france/pays_de_la_loire/vendee/longeville_sur_mer.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  String _getMarkerIconPath(SpotFlagState spot) {
    final type = spot.normalizedType;

    if (spot.isNaturisme) return 'data/icons/fire_skin_icon.png';
    if (type.contains('ACCES PLAGE')) return 'data/icons/fire_orange_icon.png';

    if (type.contains('LAC') ||
        type.contains("PLAN D'EAU") ||
        type.contains('BARRAGE')) {
      return 'data/icons/fire_blue_icon.png';
    }

    if (type.contains('FLEUVE') || type.contains('RIVIERE')) {
      return 'data/icons/fire_green_icon.png';
    }

    if (type.contains('LAGON') || type.contains('PISCINE NATURELLE')) {
      return 'data/icons/fire_cyan_icon.png';
    }

    return 'data/icons/fire_orange_icon.png';
  }

  Color _typeColor(SpotFlagState spot) {
    final type = spot.normalizedType;

    if (spot.isPosteSecours) return const Color(0xFFFF0000);
    if (spot.isNaturisme) return const Color(0xFFD87A5C);
    if (type.contains('ACCES PLAGE')) return const Color(0xFFFFD000);

    if (type.contains('LAC') ||
        type.contains("PLAN D'EAU") ||
        type.contains('BARRAGE')) {
      return const Color(0xFF1E3A8A);
    }

    if (type.contains('FLEUVE') || type.contains('RIVIERE')) {
      return const Color(0xFF2E7D32);
    }

    if (type.contains('LAGON') || type.contains('PISCINE NATURELLE')) {
      return const Color(0xFF00ACC1);
    }

    return Colors.black;
  }

  bool _matchesFilterFor(SpotFlagState spot, SpotFilter filter) {
    final type = spot.normalizedType;

    switch (filter) {
      case SpotFilter.all:
        return true;
      case SpotFilter.secours:
        return spot.isPosteSecours;
      case SpotFilter.accesPlage:
        return type.contains('ACCES PLAGE');
      case SpotFilter.eauBleue:
        return type.contains('LAC') ||
            type.contains("PLAN D'EAU") ||
            type.contains('BARRAGE');
      case SpotFilter.eauVerte:
        return type.contains('FLEUVE') || type.contains('RIVIERE');
      case SpotFilter.lagon:
        return type.contains('LAGON') || type.contains('PISCINE NATURELLE');
      case SpotFilter.naturisme:
        return spot.isNaturisme;
      case SpotFilter.autre:
        return type.contains('AUTRE') || type.contains('NON RENSEIGNE');
    }
  }

  bool _matchesFilter(SpotFlagState spot) {
    return _matchesFilterFor(spot, _selectedFilter);
  }

  String _filterLabel(SpotFilter filter) {
    switch (filter) {
      case SpotFilter.all:
        return 'SPHOTS';
      case SpotFilter.secours:
        return 'SPHOT\nPoste de secours';
      case SpotFilter.accesPlage:
        return 'SPHOT\nAccès plage';
      case SpotFilter.eauBleue:
        return "SPHOT\nLac\nPlan d'eau\nBarrage";
      case SpotFilter.eauVerte:
        return 'SPHOT\nFleuve\nRivière';
      case SpotFilter.lagon:
        return 'SPHOT\nLagon\nPiscine naturelle';
      case SpotFilter.naturisme:
        return 'SPHOT\nNaturisme';
      case SpotFilter.autre:
        return 'SPHOT\nAutre\nNon renseigné';
    }
  }

  Color _filterColor(SpotFilter filter) {
  switch (filter) {
    case SpotFilter.all:
      return const Color(0xFFFF0000);
    case SpotFilter.secours:
      return const Color(0xFFFF0000);
    case SpotFilter.accesPlage:
      return const Color(0xFFFFD000);
    case SpotFilter.eauBleue:
      return const Color(0xFF1E3A8A);
    case SpotFilter.eauVerte:
      return const Color(0xFF2E7D32);
    case SpotFilter.lagon:
      return const Color(0xFF00ACC1);
    case SpotFilter.naturisme:
      return const Color(0xFFD87A5C);
    case SpotFilter.autre:
      return Colors.black87;
  }
}

  Widget _drawerAssetIcon(String path) {
    return Image.asset(path, width: 40, height: 40, fit: BoxFit.contain);
  }

  Widget _filterIcon(SpotFilter filter) {
    switch (filter) {
      case SpotFilter.all:
        return const _SphotSpinnerIcon();
      case SpotFilter.secours:
        return const _DrawerFlagIcon();
      case SpotFilter.accesPlage:
        return _drawerAssetIcon('data/icons/fire_orange_icon.png');
      case SpotFilter.eauBleue:
        return _drawerAssetIcon('data/icons/fire_blue_icon.png');
      case SpotFilter.eauVerte:
        return _drawerAssetIcon('data/icons/fire_green_icon.png');
      case SpotFilter.lagon:
        return _drawerAssetIcon('data/icons/fire_cyan_icon.png');
      case SpotFilter.naturisme:
        return _drawerAssetIcon('data/icons/fire_skin_icon.png');
      case SpotFilter.autre:
        return _drawerAssetIcon('data/icons/fire_black_icon.png');
    }
  }

String _normalizeSearch(String value) {
  var normalized = value
      .toLowerCase()
      .replaceAll('-', ' ')
      .replaceAll('_', ' ')
      .replaceAll('’', "'")
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('ô', 'o')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ç', 'c')
      .trim();

  normalized = normalized.replaceAll(RegExp(r"\bl[' ]"), '');
  normalized = normalized.replaceAll(
  RegExp(r'\b(le|la|les|des|de|du|un|une|aux|au)\b'),
  '',
);

  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

  return normalized;
}

int _levenshtein(String s1, String s2) {
  final m = s1.length;
  final n = s2.length;

  final dp = List.generate(
    m + 1,
    (_) => List.filled(n + 1, 0),
  );

  for (int i = 0; i <= m; i++) {
    dp[i][0] = i;
  }

  for (int j = 0; j <= n; j++) {
    dp[0][j] = j;
  }

  for (int i = 1; i <= m; i++) {
    for (int j = 1; j <= n; j++) {
      final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;

      dp[i][j] = [
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      ].reduce((a, b) => a < b ? a : b);
    }
  }

  return dp[m][n];
}

SpotFlagState? _findBestSpotMatch(
  List<SpotFlagState> spots,
  String rawQuery,
) {
  final query = _normalizeSearch(rawQuery);

  if (query.length < 2) {
    return null;
  }

  SpotFlagState? bestMatch;
  int bestScore = 999;

  for (final spot in spots) {
    final fields = [
  spot.name,
  spot.nomSphot,
  spot.typeSphot,
  spot.ville,
  spot.departement,

  '${spot.ville} ${spot.name}',
  '${spot.ville} ${spot.nomSphot}',
  '${spot.ville} ${spot.typeSphot}',

  '${spot.departement} ${spot.ville}',
  '${spot.departement} ${spot.name}',
  '${spot.departement} ${spot.nomSphot}',
  '${spot.departement} ${spot.typeSphot}',

  '${spot.name} ${spot.nomSphot}',
  '${spot.name} ${spot.nomSphot} ${spot.typeSphot}',
  '${spot.ville} ${spot.name} ${spot.nomSphot} ${spot.typeSphot}',
  '${spot.departement} ${spot.ville} ${spot.name} ${spot.nomSphot}',
].map(_normalizeSearch).toList();

    for (final field in fields) {
      int score;

      if (field.contains(query)) {
        score = 0;
      } else {
        final words = field.split(RegExp(r'\s+'));

        score = words
            .map((word) => _levenshtein(query, word))
            .reduce((a, b) => a < b ? a : b);
      }

      if (score < bestScore) {
        bestScore = score;
        bestMatch = spot;
      }
    }
  }

  if (bestMatch != null && bestScore <= 3) {
    return bestMatch;
  }

  return null;
}

  void _showMapMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _resetNorth() {
    _mapController.rotate(0);
    setState(() => _currentRotation = 0);
  }

  void _toggleMapStyleBar() {
  setState(() {
    _isMapStyleOpen = !_isMapStyleOpen;

    if (_isMapStyleOpen) {
      _isFilterOpen = false;
      _searchController.clear();
      _searchFocusNode.unfocus();
    }
  });
}

void _selectMapStyle(int index) {
  debugPrint('STYLE CLIQUÉ : $index - ${_tileStyles[index].name}');
  debugPrint('URL : ${_tileStyles[index].url}');

  setState(() {
    _selectedTileStyle = index;
    _isMapStyleOpen = false;
    _isFilterOpen = false;
  });

  _showMapMessage('Carte : ${_tileStyles[index].name}');
}

  Future<void> _goToUserLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        _showMapMessage('Active la localisation de ton appareil.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMapMessage('Autorisation de localisation refusée.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _mapController.move(
        LatLng(position.latitude, position.longitude),
        15.5,
      );
    } catch (_) {
      _showMapMessage('Position actuelle indisponible.');
    }
  }

void _searchAndMoveToSpot(
  List<SpotFlagState> spots,
  String value,
) {
  _searchTimer?.cancel();

  _searchTimer = Timer(
    const Duration(milliseconds: 650),
    () {
      if (!mounted) return;

      final query = _normalizeSearch(value);

      if (query.length < 2) return;

      bool matchText(String field) {
        final normalizedField = _normalizeSearch(field);

        return normalizedField == query ||
            normalizedField.contains(query) ||
            query.contains(normalizedField);
      }

      final cityMatch = spots.where((spot) {
        return matchText(spot.ville) &&
            spot.villeLat != 0 &&
            spot.villeLng != 0;
      }).toList();

      if (cityMatch.isNotEmpty) {
        final spot = cityMatch.first;

        debugPrint('VILLE TROUVÉE : ${spot.ville}');
        debugPrint('GPS VILLE : ${spot.villeLat}, ${spot.villeLng}');

        _searchController.clear();
        setState(() {});

        _mapController.move(
          LatLng(spot.villeLat, spot.villeLng),
          12.5,
        );
        return;
      }

      final departementMatch = spots.where((spot) {
        return matchText(spot.departement) &&
            spot.departementLat != 0 &&
            spot.departementLng != 0;
      }).toList();

      if (departementMatch.isNotEmpty) {
        final spot = departementMatch.first;

        debugPrint('DÉPARTEMENT TROUVÉ : ${spot.departement}');
        debugPrint(
          'GPS DÉPARTEMENT : ${spot.departementLat}, ${spot.departementLng}',
        );

        _searchController.clear();
        setState(() {});

        _mapController.move(
          LatLng(spot.departementLat, spot.departementLng),
          9.5,
        );
        return;
      }

      final spot = _findBestSpotMatch(spots, value);

      if (spot == null) {
        debugPrint('AUCUN RÉSULTAT POUR : $value');
        return;
      }

      debugPrint('SPHOT TROUVÉ : ${spot.name}');
      debugPrint('GPS SPHOT : ${spot.lat}, ${spot.lng}');

      _searchController.clear();
      setState(() {});

      _mapController.move(
        LatLng(spot.lat, spot.lng),
        16.5,
      );
    },
  );
}

void _startVoiceSearch(List<SpotFlagState> spots) async {
  if (!_isListening) {
    bool available = await _speech.initialize();

    if (available) {
      setState(() => _isListening = true);

      _speech.listen(
        localeId: 'fr_FR',
        onResult: (result) {
          final text = result.recognizedWords;

         _searchController.text = text;
_searchController.selection = TextSelection.fromPosition(
  TextPosition(offset: _searchController.text.length),
);

setState(() {});

if (result.finalResult) {
  _searchAndMoveToSpot(spots, text);
  setState(() => _isListening = false);
}
        },
      );
    } else {
      _showMapMessage('Micro non disponible');
    }
  } else {
    setState(() => _isListening = false);
    _speech.stop();
  }
}

  Widget _mapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double rotation = 0,
  }) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.white.withOpacity(0.92),
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Center(
                child: Transform.rotate(
                  angle: rotation,
                  child: Icon(
                    icon,
                    color: Colors.black87,
                    size: 25,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

void _toggleFilterBar() {
  setState(() {
    _isFilterOpen = !_isFilterOpen;

    if (_isFilterOpen) {
      _isMapStyleOpen = false;
      _searchController.clear();
      _searchFocusNode.unfocus();
    }
  });
}

String _filterShortLabel(SpotFilter filter) {
  switch (filter) {
    case SpotFilter.all:
      return 'Tous les SPHOTS';
    case SpotFilter.secours:
      return 'Poste de secours';
    case SpotFilter.accesPlage:
      return 'Accès plage';
    case SpotFilter.eauBleue:
      return "Lac\nPlan d'eau\nBarrage";
    case SpotFilter.eauVerte:
      return 'Fleuve\nRivière';
    case SpotFilter.lagon:
      return 'Lagon\nPiscine naturelle';
    case SpotFilter.naturisme:
      return 'Naturisme';
    case SpotFilter.autre:
      return 'Autre\nNon renseigné';
  }
}

Widget _verticalFilterChoiceButton(SpotFilter filter, int index) {
  final selected = filter == _selectedFilter;
  final color = _filterColor(filter);

  return AnimatedOpacity(
    duration: Duration(milliseconds: 350 + index * 80),
    opacity: _isFilterOpen ? 1.0 : 0.0,
    child: AnimatedSlide(
      duration: Duration(milliseconds: 1400 + index * 260),
      curve: Curves.easeOutBack,
      offset: _isFilterOpen ? Offset.zero : const Offset(0, 0.35),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: Colors.white.withOpacity(0.94),
          elevation: 4,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                _selectedFilter = filter;
                _isFilterOpen = false;
              });
            },
            child: Container(
              width: 190,
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? color : Colors.grey.withOpacity(0.5),
                  width: selected ? 2 : 1.2,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: Center(child: _filterIcon(filter)),
                  ),
                  const SizedBox(width: 0),
                  Expanded(
                    child: Text(
                      _filterShortLabel(filter),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: filter == SpotFilter.all
    ? Colors.black87
    : color,
                        fontSize: 14,
                        height: 1.05,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _buildVerticalFilterMenu() {
  return Positioned(
    left: 8,
    bottom: 120,
    child: IgnorePointer(
      ignoring: !_isFilterOpen,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.68,
        child: SingleChildScrollView(
          reverse: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(
              SpotFilter.values.length,
              (index) {
                final reversedIndex = SpotFilter.values.length - 1 - index;

                return _verticalFilterChoiceButton(
                  SpotFilter.values[reversedIndex],
                  index,
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _buildMapStyleVerticalMenu() {
  return IgnorePointer(
    ignoring: !_isMapStyleOpen,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        _tileStyles.length,
        (index) {
          final reversedIndex = _tileStyles.length - 1 - index;

          return _animatedMapStyleButton(
            reversedIndex,
            index,
          );
        },
      ),
    ),
  );
}

Widget _animatedMapStyleButton(int tileIndex, int animationIndex) {
  return AnimatedOpacity(
    duration: Duration(
      milliseconds: 350 + animationIndex * 80,
    ),
    opacity: _isMapStyleOpen ? 1.0 : 0.0,
    child: AnimatedSlide(
      duration: Duration(
        milliseconds: 1400 + animationIndex * 260,
      ),
      curve: Curves.easeOutBack,
      offset: _isMapStyleOpen
          ? Offset.zero
          : const Offset(0, 0.35),
      child: _mapStyleVerticalButton(tileIndex),
    ),
  );
}

Widget _mapStyleVerticalButton(int index) {
  final selected = index == _selectedTileStyle;

  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: Colors.white.withOpacity(0.94),
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _selectMapStyle(index),
        child: Container(
          width: 150, // ⬅️ un peu plus large
          height: 48, // ⬅️ plus haut
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
  color: selected
      ? _mapStyleColor(index)
      : Colors.grey.withOpacity(0.5),
  width: selected ? 2.2 : 1.2,
),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: Center(child: _mapStyleIcon(index)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _tileStyles[index].name,
                  style: TextStyle(
                    fontSize: 16, // ⬅️ texte plus grand
                    fontWeight:
                        selected ? FontWeight.w900 : FontWeight.w700,
                    color: _mapStyleColor(index).withOpacity(selected ? 1.0 : 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Color _mapStyleColor(int index) {
  switch (index) {
    case 0:
      return const Color(0xFF2E7D32); // Plan
    case 1:
      return const Color(0xFF1E3A8A); // Satellite
    case 2:
      return const Color(0xFF8B5E3C); // Relief
    default:
      return Colors.black;
  }
}

Widget _mapStyleIcon(int index) {
  final selected = index == _selectedTileStyle;

  /// STYLE PLAN
  if (index == 0) {
    return Icon(
      Icons.map,
      size: 26,
      color: _mapStyleColor(index).withOpacity(selected ? 1.0 : 0.6),
    );
  }

  /// STYLE SATELLITE
  if (index == 1) {
    return Icon(
      Icons.satellite_alt,
      size: 26,
      color: _mapStyleColor(index).withOpacity(selected ? 1.0 : 0.6),
    );
  }

  /// STYLE RELIEF
  return SizedBox(
    width: 28,
    height: 28,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Transform.rotate(
          angle: -0.18,
          child: Icon(
            Icons.map,
            size: 24,
            color: const Color(0xFF8B5E3C).withOpacity(
              selected ? 1.0 : 0.6,
            ), // marron relief
          ),
        ),

        Transform.translate(
          offset: const Offset(4, -2),
          child: Transform.rotate(
            angle: 0.12,
            child: Icon(
              Icons.map,
              size: 20,
              color: const Color(0xFF2E7D32).withOpacity(
                selected ? 1.0 : 0.6,
              ), // vert rivière
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildLeftMapControls(List<SpotFlagState> spots) {
  
  final isSearching = _searchController.text.trim().isNotEmpty || _isListening;

  return Positioned(
    left: 8,
    right: 8,
    top: MediaQuery.of(context).padding.top + 50,
    child: Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.white.withOpacity(0.94),
            elevation: 4,
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: Colors.black.withOpacity(0.4),
                  width: 1.2,
                ),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textAlignVertical: TextAlignVertical.center,
                onChanged: (value) {
                  setState(() {});
                  _searchAndMoveToSpot(spots, value);
                },
                decoration: InputDecoration(
  hintText: 'Rechercher un SPHOT',
  prefixIcon: const Icon(Icons.search, size: 21),
  prefixIconConstraints: const BoxConstraints(
    minHeight: 0,
    minWidth: 40,
  ),
  suffixIcon: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_searchController.text.trim().isNotEmpty)
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () {
            _searchTimer?.cancel();
            _searchController.clear();
            setState(() {});
          },
        ),
      IconButton(
  icon: AnimatedSwitcher(
    duration: const Duration(milliseconds: 250),
    child: Icon(
      _isListening
          ? Icons.radio_button_checked
          : Icons.keyboard_voice_rounded,
      key: ValueKey(_isListening),
      color: _isListening
          ? const Color(0xFFFF0000)
          : Colors.black87,
      size: 22,
    ),
  ),
  onPressed: () => _startVoiceSearch(spots),
),
    ],
  ),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(vertical: 0),
  border: InputBorder.none,
),
              ),
            ),
          ),
        ),
        if (!isSearching) ...[
  const SizedBox(width: 6),
  _mapControlButton(
    icon: Icons.my_location,
    tooltip: 'Ma position',
    onTap: _goToUserLocation,
  ),
  const SizedBox(width: 4),
  _mapControlButton(
    icon: Icons.navigation,
    tooltip: 'Remettre le Nord',
    rotation: _currentRotation * pi / 180,
    onTap: _resetNorth,
  ),
],
      ],
    ),
  );
}

  Marker _buildOtherSpotMarker(
    SpotFlagState spot,
    bool showText,
    double zoom,
    double rotation,
  ) {
    return Marker(
      point: LatLng(spot.lat, spot.lng),
      width: 56,
      height: 56,
      alignment: Alignment.center,
      child: _OtherSpotMarker(
        spot: spot,
        iconPath: _getMarkerIconPath(spot),
        showTextAllowed: showText,
        zoom: zoom,
        rotation: rotation,
        labelOpacity: _labelOpacity(zoom),
        typeTextColor: _typeColor(spot),
      ),
    );
  }

  Marker _buildSecoursMarker(
    SpotFlagState spot,
    bool showFlag,
    bool showText,
    double zoom,
    double rotation,
  ) {
    if (!showFlag) {
      return Marker(
        point: LatLng(spot.lat, spot.lng),
        width: 18,
        height: 18,
        alignment: Alignment.center,
        child: _SimplePostePoint(spot: spot),
      );
    }

    return Marker(
      point: LatLng(spot.lat, spot.lng),
      width: 70,
      height: 95,
      alignment: Alignment.center,
      child: _HoverMarker(
        spot: spot,
        showTextAllowed: showText,
        zoom: zoom,
        rotation: rotation,
        labelOpacity: _labelOpacity(zoom),
      ),
    );
  }

  List<Marker> _buildMarkers(
  List<SpotFlagState> spots,
  double zoom,
  double rotation,
) {
  final showFlag = _showFlagForZoom(zoom);
  final showText = _showTextForZoom(zoom);

  debugPrint('MARKERS À AFFICHER : ${spots.length}');

  return spots
      .where((spot) => spot.lat.isFinite && spot.lng.isFinite)
      .map((spot) {
    if (spot.isPosteSecours) {
      return _buildSecoursMarker(spot, showFlag, showText, zoom, rotation);
    }
    return _buildOtherSpotMarker(spot, showText, zoom, rotation);
  }).toList();
}

  Widget _buildDrawer() {
  return Drawer(
    backgroundColor: Colors.transparent,
    elevation: 0,
    child: SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.35),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Center(
                child: Image.asset(
                  'data/icons/title.png',
                  height: 76,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ...SpotFilter.values.map((filter) {
                    final selected = filter == _selectedFilter;
                    final color = _filterColor(filter);

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: SizedBox(
                          width: 42,
                          height: 42,
                          child: Center(child: _filterIcon(filter)),
                        ),
                        title: _OutlinedMenuText(
                          text: _filterLabel(filter),
                          color: color,
                          selected: selected,
                        ),
                        trailing: selected
                            ? Icon(Icons.check, color: color, size: 24)
                            : null,
                        selected: selected,
                        selectedTileColor: color.withOpacity(0.10),
                        onTap: () {
                          setState(() => _selectedFilter = filter);
                          Navigator.of(context).pop();
                        },
                      ),
                    );
                  }),
                  const Divider(height: 28),
                  _infoItem(Icons.info_outline, 'À propos de SPHOT'),
                  _infoItem(Icons.description_outlined, 'Mentions légales'),
                  _infoItem(
                    Icons.privacy_tip_outlined,
                    'Politique de confidentialité',
                  ),
                  _infoItem(Icons.gavel_outlined, 'Conditions d’utilisation'),
                  _infoItem(Icons.contact_support_outlined, 'Contact'),
                  _infoItem(Icons.settings_outlined, 'Paramètres'),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _infoItem(IconData icon, String label) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => Navigator.of(context).pop(),
    );
  }

  Color _clusterBorderColor(List<Marker> markers) {
  final colors = <Color>{};

  for (final marker in markers) {
    final child = marker.child;
    if (child is _OtherSpotMarker) {
      colors.add(child.typeTextColor);
    } else if (child is _SimplePostePoint || child is _HoverMarker) {
      colors.add(const Color(0xFFFF0000));
    }
  }

  if (colors.contains(const Color(0xFFFF0000))) {
    return const Color(0xFFFF0000); // Poste de secours
  }

  if (colors.contains(const Color(0xFFD87A5C))) {
    return const Color(0xFFD87A5C); // Naturisme
  }

  if (colors.contains(const Color(0xFFFFD000))) {
    return const Color(0xFFFFD000); // Accès plage
  }

  if (colors.contains(const Color(0xFF1E3A8A))) {
    return const Color(0xFF1E3A8A); // Lac / plan d'eau / barrage
  }

  if (colors.contains(const Color(0xFF2E7D32))) {
    return const Color(0xFF2E7D32); // Fleuve / rivière
  }

  if (colors.contains(const Color(0xFF00ACC1))) {
    return const Color(0xFF00ACC1); // Lagon
  }

  return Colors.white;
}

  Widget _buildCluster(BuildContext context, List<Marker> markers) {
  final count = markers.length;
  final borderColor = _clusterBorderColor(markers);
  final rotation = MapCamera.of(context).rotation;

  final outlineColor = Colors.white;

  return Transform.rotate(
    angle: -rotation * pi / 180,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
        border: Border.all(
          color: outlineColor,
          width: 2.2,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(
            color: borderColor,
            width: 2.2,
          ),
        ),
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            /// CONTOUR TEXTE
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2.2
                  ..color = outlineColor,
              ),
            ),

            /// TEXTE COULEUR
            Text(
              count.toString(),
              style: TextStyle(
                color: borderColor,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildAdBanner() {
  return Positioned(
    left: 8,
    right: 8,
    bottom: 58, // juste au-dessus de la bottom bar
    child: Container(
      height: 62,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: Colors.black.withOpacity(0.08),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),

          /// LOGO / IMAGE PUB
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 52,
              height: 52,
              color: Colors.blueGrey.withOpacity(0.08),
              child: const Icon(
                Icons.campaign,
                size: 28,
                color: Colors.black87,
              ),
            ),
          ),

          const SizedBox(width: 12),

          /// TEXTE PUB
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PUBLICITÉ LOCALE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                    letterSpacing: 0.2,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  'Camping • Surf Shop • Restaurant',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),

          /// CTA
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                'VOIR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildBottomBar() {
  final items = [
    {'icon': Icons.tune, 'label': 'FILTRES'},
    {'icon': Icons.layers_outlined, 'label': 'CARTES'},
    {'icon': Icons.star_border, 'label': 'FAVORIS'},
    {'icon': Icons.info_outline, 'label': 'INFOS'},
    {'icon': Icons.add, 'label': 'SAUVETEUR'},
  ];

  return Positioned(
    left: 8,
    right: 8,
    bottom: 6,
    child: Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(items.length, (index) {
          final selected = index == _selectedBottomIndex;

          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
  setState(() {
    _selectedBottomIndex = index;
  });

  if (index == 0) {
    _toggleFilterBar();
  } else if (index == 1) {
    _toggleMapStyleBar();
  } else if (index == 2) {
    _showMapMessage('Favoris bientôt disponibles');
  } else if (index == 3) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AppInfoPage(),
      ),
    );
  } else if (index == 4) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LifeguardLoginPage(),
      ),
    );
  }
},

            child: SizedBox(
              width: 58,
              height: 50,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: Center(
                      child: index == 4
    ? Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 8,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFFFF0000),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            width: 26,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD000),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      )
    : index == 1
        ? const Icon(
            Icons.layers_outlined,
            size: 30,
            color: Color(0xFF8B5E3C),
          )
        : Icon(
    items[index]['icon'] as IconData,
    size: 30,
    color: index == 2
        ? const Color(0xFFFFD000)
        : index == 3
            ? const Color(0xFF1E3A8A)
            : Colors.black87
  ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[index]['label'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontSize: 10.4,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                      color: index == 1
                          ? const Color(0xFF2E7D32)
                          : index == 2
                              ? const Color(0xFFFFD000)
                              : index == 3
                                  ? const Color(0xFF1E3A8A)
                                  : index == 4
                                      ? const Color(0xFFFF0000)
                                      : Colors.black87
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    ),
  );
}

  PreferredSizeWidget _buildAppBar() {
  return PreferredSize(
    preferredSize: const Size.fromHeight(58),
    child: SafeArea(
      bottom: false,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: -5,
            left: 0,
            right: 0,
            child: Center(
              child: Image.asset(
                'data/icons/title.png',
                height: 68,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  @override
void dispose() {
  _mapMoveTimer?.cancel();
  _searchTimer?.cancel();
  _searchController.dispose();
  _searchFocusNode.dispose();
  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
  key: _scaffoldKey,
  drawerScrimColor: Colors.transparent,
  backgroundColor: Colors.transparent,
  extendBodyBehindAppBar: true,
  appBar: _buildAppBar(),
  endDrawer: _buildDrawer(),
  body: StreamBuilder<List<SpotFlagState>>(
        stream: _firestoreService.getSpotsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allSpots = snapshot.data!;
final spots = allSpots.where(_matchesFilter).toList();

debugPrint('SPHOTS CHARGÉS : ${allSpots.length}');
debugPrint('SPHOTS AFFICHÉS : ${spots.length}');

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
  initialCenter: const LatLng(46.4006176, -1.5064563),
  initialZoom: 13,
  interactionOptions: const InteractionOptions(
  flags: InteractiveFlag.all,
),

onTap: (_, __) {
  if (_isFilterOpen || _isMapStyleOpen) {
    _searchFocusNode.unfocus();

    setState(() {
      _isFilterOpen = false;
      _isMapStyleOpen = false;
    });
  }
},

onPositionChanged: (position, hasGesture) {
  if ((_currentRotation - position.rotation).abs() > 0.5 || hasGesture) {
    setState(() {
      _currentRotation = position.rotation;
      if (hasGesture) {
        _isMovingMap = true;
      }
    });
  }

  if (hasGesture) {
    if (_isFilterOpen || _isMapStyleOpen) {
      _searchFocusNode.unfocus();

      setState(() {
        _isFilterOpen = false;
        _isMapStyleOpen = false;
      });
    }

    _mapMoveTimer?.cancel();
    _mapMoveTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        _isMovingMap = false;
      });
    });
  }
},
),
                children: [
                  TileLayer(
  key: ValueKey('tile_style_$_selectedTileStyle'),
  urlTemplate: _tileStyles[_selectedTileStyle].url,
  subdomains: _tileStyles[_selectedTileStyle].subdomains,
  maxZoom: _tileStyles[_selectedTileStyle].maxZoom.toDouble(),
  maxNativeZoom: _tileStyles[_selectedTileStyle].maxZoom,
  userAgentPackageName: 'com.sylvainra.sphot',
  keepBuffer: 5,
  errorTileCallback: (tile, error, stackTrace) {
    debugPrint('ERREUR TILE MAP : $error');
  },
),
                  Builder(
                    builder: (context) {
                      final zoom = MapCamera.of(context).zoom;
                      final rotation = MapCamera.of(context).rotation;

                      return MarkerLayer(
                        markers: _buildTerritoryLogoMarkers(zoom, rotation),
                      );
                    },
                  ),
                  Builder(
                    builder: (context) {
                      final zoom = MapCamera.of(context).zoom;
                      final rotation = MapCamera.of(context).rotation;
                      final markers = _buildMarkers(spots, zoom, rotation);

                      return MarkerClusterLayerWidget(
                        options: MarkerClusterLayerOptions(
                          markers: markers,
                          size: const Size(42, 42),
                          maxClusterRadius: 45,
                          disableClusteringAtZoom: 16,
                          builder: _buildCluster,
                        ),
                      );
                    },
                  ),
                ],
              ),
              _buildLeftMapControls(allSpots),


Positioned(
  left: 8,
  bottom: 120,
  child: _buildMapStyleVerticalMenu(),
),

_buildVerticalFilterMenu(),
_buildAdBanner(),
_buildBottomBar(),
            ],
          );
        },
      ),
    );
  }
}

class _ColoredSphotsText extends StatelessWidget {
  const _ColoredSphotsText();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: 'SPHOTS',
        style: TextStyle(
          fontSize: 15.4,
          fontWeight: FontWeight.w800,
          height: 1.1,
          letterSpacing: -0.1,
          foreground: Paint()
            ..shader = const LinearGradient(
              colors: [
                Color(0xFFFF7F00),
                Color(0xFF1E3A8A),
                Color(0xFF2E7D32),
                Color(0xFF00ACC1),
                Color(0xFFD87A5C),
                Colors.black87,
              ],
            ).createShader(const Rect.fromLTWH(0, 0, 120, 20)),
        ),
      ),
    );
  }
}

class _OutlinedMenuText extends StatelessWidget {
  final String text;
  final Color color;
  final bool selected;

  const _OutlinedMenuText({
    required this.text,
    required this.color,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lines.first == 'SPHOTS')
          const _ColoredSphotsText()
        else
          Text(
  lines.first,
  style: TextStyle(
    color: color,
    fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
    fontSize: 15,
    height: 1.1,
    shadows: color == const Color(0xFFFFD000)
        ? const [
            Shadow(
              color: Colors.white,
              offset: Offset(0.6, 0),
              blurRadius: 0.8,
            ),
            Shadow(
              color: Colors.white,
              offset: Offset(-0.6, 0),
              blurRadius: 0.8,
            ),
            Shadow(
              color: Colors.white,
              offset: Offset(0, 0.6),
              blurRadius: 0.8,
            ),
            Shadow(
              color: Colors.white,
              offset: Offset(0, -0.6),
              blurRadius: 0.8,
            ),
          ]
        : null,
  ),
),
        ...lines.skip(1).map(
              (line) => Text(
                line,
                style: TextStyle(
  color: color.withOpacity(0.85),
  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
  fontSize: 13,
  height: 1.15,
  shadows: color == const Color(0xFFFFD000)
      ? const [
          Shadow(
            color: Colors.black,
            offset: Offset(0.5, 0),
            blurRadius: 0.7,
          ),
          Shadow(
            color: Colors.black,
            offset: Offset(-0.5, 0),
            blurRadius: 0.7,
          ),
        ]
      : null,
),
              ),
            ),
      ],
    );
  }
}



class _SphotSpinnerIcon extends StatefulWidget {
  const _SphotSpinnerIcon();

  @override
  State<_SphotSpinnerIcon> createState() => _SphotSpinnerIconState();
}

class _SphotSpinnerIconState extends State<_SphotSpinnerIcon> {
  late final Timer _timer;
  int _step = 0;

  static const List<String> _icons = [
    'data/icons/fire_orange_icon.png',
    'data/icons/fire_blue_icon.png',
    'data/icons/fire_green_icon.png',
    'data/icons/fire_cyan_icon.png',
    'data/icons/fire_skin_icon.png',
    'data/icons/fire_black_icon.png',
  ];

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!mounted) return;
      setState(() => _step = _step + 1);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 42.0;
    const iconSize = 22.0;
    const radius = 10.0;
    const count = 6;

    final angles = List.generate(
      count,
      (i) => -pi / 2 + (2 * pi * i / count),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(count, (index) {
          final angle = angles[index];
          final path = _icons[index % _icons.length];

          final activeIndex = _step % count;
          final isActive = index == activeIndex;

          return Positioned(
            left: size / 2 + cos(angle) * radius - iconSize / 2,
            top: size / 2 + sin(angle) * radius - iconSize / 2,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: isActive ? 1.0 : 0.18,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 300),
                scale: isActive ? 1.18 : 0.78,
                child: Transform.rotate(
                  angle: angle + pi / 2,
                  child: Image.asset(
                    path,
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DrawerFlagIcon extends StatefulWidget {
  const _DrawerFlagIcon();

  @override
  State<_DrawerFlagIcon> createState() => _DrawerFlagIconState();
}

class _DrawerFlagIconState extends State<_DrawerFlagIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double iconWidth = 28;
  static const double iconHeight = 34;

  static const double poleWidth = 3;
  static const double poleHeight = 31;
  static const double poleLeft = 7;

  static const double flagLeft = poleLeft + poleWidth - 0.5;
  static const double flagTop = -1;
  static const double flagWidth = 16;
  static const double flagHeight = 22;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: iconWidth,
      height: iconHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: poleLeft,
            bottom: 0,
            child: Container(
              width: poleWidth,
              height: poleHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: flagLeft,
            top: flagTop,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(flagWidth, flagHeight),
                  painter: MiniWavingFlagPainter(
                    color: const Color(0xFF22C55E),
                    phase: _controller.value * 2 * pi,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MiniWavingFlagPainter extends CustomPainter {
  final Color color;
  final double phase;

  MiniWavingFlagPainter({
    required this.color,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final path = ui.Path();

    const int steps = 30;
    const double verticalMargin = 5;

    final topPoints = <Offset>[];
    final bottomPoints = <Offset>[];

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = size.width * t;

      final amplitude = 0.3 + 1.2 * t;
      final wave = sin(t * pi * 1.8 - phase) * amplitude;

      topPoints.add(Offset(x, verticalMargin + wave));
      bottomPoints.add(Offset(x, size.height - verticalMargin + wave));
    }

    path.moveTo(topPoints.first.dx, topPoints.first.dy);

    for (final point in topPoints) {
      path.lineTo(point.dx, point.dy);
    }

    for (final point in bottomPoints.reversed) {
      path.lineTo(point.dx, point.dy);
    }

    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant MiniWavingFlagPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.color != color;
  }
}

class _OtherSpotMarker extends StatefulWidget {
  final SpotFlagState spot;
  final String iconPath;
  final bool showTextAllowed;
  final double zoom;
  final double rotation;
  final double labelOpacity;
  final Color typeTextColor;

  const _OtherSpotMarker({
    required this.spot,
    required this.iconPath,
    required this.showTextAllowed,
    required this.zoom,
    required this.rotation,
    required this.labelOpacity,
    required this.typeTextColor,
  });

  @override
  State<_OtherSpotMarker> createState() => _OtherSpotMarkerState();
}

class _OtherSpotMarkerState extends State<_OtherSpotMarker> {
  bool isHovering = false;

  double _lineSpacing() {
    if (widget.zoom >= 16) return 3.0;
    if (widget.zoom >= 15) return 2.6;
    if (widget.zoom >= 14) return 2.2;
    return 2.0;
  }

  double _labelSize(double base) {
    if (widget.zoom >= 16) return base + 2;
    if (widget.zoom >= 15) return base + 1.5;
    if (widget.zoom >= 14) return base + 1;
    if (widget.zoom >= 13) return base;
    return base - 0.5;
  }

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;

    final isTouchDevice =
        Theme.of(context).platform == TargetPlatform.android ||
            Theme.of(context).platform == TargetPlatform.iOS;

    final showText = widget.showTextAllowed && (isTouchDevice || isHovering);

    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Transform.rotate(
          angle: -widget.rotation * pi / 180,
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Image.asset(
                widget.iconPath,
                width: spot.isNaturisme ? 52 : 48,
                height: spot.isNaturisme ? 52 : 48,
                fit: BoxFit.contain,
              ),
              if (showText)
                Positioned(
                  top: 50,
                  left: -160,
                  child: Opacity(
                    opacity: widget.labelOpacity,
                    child: SizedBox(
                      width: 380,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${spot.name} - ${spot.nomSphot}',
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _labelSize(11),
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                          SizedBox(height: _lineSpacing() + 1.5),
                          Text(
  spot.typeSphot,
  textAlign: TextAlign.center,
  style: _mapLabelStyle(
    fontSize: _labelSize(12),
    fontWeight: FontWeight.w700,
    color: widget.typeTextColor,
    useBlackOutline: spot.normalizedType.contains('ACCES PLAGE'),
  ),
),
                          SizedBox(height: _lineSpacing() - 1.8),
                          _warningLineUniform(
                            'BAIGNADE NON SURVEILLÉE',
                            _labelSize(22),
                          ),
                          SizedBox(height: _lineSpacing() - 1.8),
                          _warningLineUniform(
                            'BAIGNADE À VOS RISQUES ET PÉRILS',
                            _labelSize(22),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimplePostePoint extends StatelessWidget {
  final SpotFlagState spot;

  const _SimplePostePoint({required this.spot});

  Color _getColor() {
    switch (spot.flagColor) {
      case FlagColor.green:
        return const Color(0xFF22C55E);
      case FlagColor.yellow:
        return const Color(0xFFFDE047);
      case FlagColor.red:
        return const Color(0xFFEF4444);
      case FlagColor.violet:
        return const Color(0xFFD946EF);
      case FlagColor.none:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFlag = spot.hasValidFlag;

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: hasFlag ? _getColor() : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: hasFlag ? Colors.white : Colors.black,
          width: 2,
        ),
      ),
    );
  }
}

class _HoverMarker extends StatefulWidget {
  final SpotFlagState spot;
  final bool showTextAllowed;
  final double zoom;
  final double rotation;
  final double labelOpacity;

  const _HoverMarker({
    required this.spot,
    required this.showTextAllowed,
    required this.zoom,
    required this.rotation,
    required this.labelOpacity,
  });

  @override
  State<_HoverMarker> createState() => _HoverMarkerState();
}

class _HoverMarkerState extends State<_HoverMarker> {
  bool isHovering = false;

  double _lineSpacing() {
    if (widget.zoom >= 16) return 3.0;
    if (widget.zoom >= 15) return 2.6;
    if (widget.zoom >= 14) return 2.2;
    return 2.0;
  }

  double _labelSize(double base) {
    if (widget.zoom >= 16) return base + 2;
    if (widget.zoom >= 15) return base + 1.5;
    if (widget.zoom >= 14) return base + 1;
    if (widget.zoom >= 13) return base;
    return base - 0.5;
  }

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;

    final isTouchDevice =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;

    final showText = widget.showTextAllowed && (isTouchDevice || isHovering);

    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      child: SizedBox(
        width: 70,
        height: 95,
        child: Transform.rotate(
          angle: -widget.rotation * pi / 180,
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Transform.translate(
                offset: const Offset(0, -47.5),
                child: FlagMarker(spot: spot),
              ),
              if (showText)
                Positioned(
                  top: 54,
                  left: -175,
                  child: Opacity(
                    opacity: widget.labelOpacity,
                    child: SizedBox(
                      width: 420,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${spot.name} - ${spot.nomSphot}',
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _labelSize(11),
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),

                          SizedBox(height: _lineSpacing() + 5),

                          Text(
                            '🚨 POSTE DE SECOURS 🚨',
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _labelSize(12),
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFFF0000),
                            ),
                          ),

                          SizedBox(height: _lineSpacing() - 1.8),

                          _warningLineUniform(
                            'BAIGNADE NON SURVEILLÉE',
                            _labelSize(22),
                          ),

                          SizedBox(height: _lineSpacing() - 1.8),

                          _warningLineUniform(
                            'BAIGNADE À VOS RISQUES ET PÉRILS',
                            _labelSize(22),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _warningLineUniform(String text, double size) {
  return Row(
    mainAxisSize: MainAxisSize.min,
        children: [
      Stack(
        children: [
          Transform.translate(
            offset: const Offset(1, 0),
            child: Icon(Icons.warning_amber_rounded, size: size, color: Colors.white),
          ),
          Transform.translate(
            offset: const Offset(-1, 0),
            child: Icon(Icons.warning_amber_rounded, size: size, color: Colors.white),
          ),
          Transform.translate(
            offset: const Offset(0, 1),
            child: Icon(Icons.warning_amber_rounded, size: size, color: Colors.white),
          ),
          Transform.translate(
            offset: const Offset(0, -1),
            child: Icon(Icons.warning_amber_rounded, size: size, color: Colors.white),
          ),
          Icon(
            Icons.warning_amber_rounded,
            size: size,
            color: const Color(0xFFFF0000),
          ),
        ],
      ),
      const SizedBox(width: 2),
      Flexible(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: _mapLabelStyle(
            fontSize: size * 0.55,
            fontWeight: FontWeight.w900,
            color: const Color(0xFFFF0000),
          ),
        ),
      ),
    ],
  );
}

TextStyle _mapLabelStyle({
  required double fontSize,
  required FontWeight fontWeight,
  required Color color,
  bool useBlackOutline = false,
}) {
  if (useBlackOutline) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: 1,
      letterSpacing: -0.1,
      shadows: const [
  Shadow(
    color: Colors.white,
    offset: Offset(0.8, 0),
    blurRadius: 1,
  ),
  Shadow(
    color: Colors.white,
    offset: Offset(-0.8, 0),
    blurRadius: 1,
  ),
  Shadow(
    color: Colors.white,
    offset: Offset(0, 0.8),
    blurRadius: 1,
  ),
  Shadow(
    color: Colors.white,
    offset: Offset(0, -0.8),
    blurRadius: 1,
  ),
],
    );
  }

  return TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: 1,
    letterSpacing: -0.1,
    shadows: const [
      Shadow(color: Colors.white, offset: Offset(0, 0), blurRadius: 5),

      Shadow(color: Colors.white, offset: Offset(1.5, 0), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(-1.5, 0), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(0, 1.5), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(0, -1.5), blurRadius: 2),

      Shadow(color: Colors.white, offset: Offset(1.2, 1.2), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(-1.2, 1.2), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(1.2, -1.2), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(-1.2, -1.2), blurRadius: 2),
    ],
  );
}





