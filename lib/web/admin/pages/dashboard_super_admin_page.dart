import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:math' as math;
import 'package:url_launcher/url_launcher.dart';

enum DashboardSpotFilter {
  none,
  all,
  secours,
  eauVerte,
  lagon,
  eauBleue,
  plage,
  naturisme,
  loisirs,
}

enum DashboardAdminFilter {
  none,
  all,
  trial,
  active,
  overdue,
  cancelled,
}

enum DashboardAdvertiserFilter {
  none,
  pending,
  all,
  active,
  expiringSoon,
  finished,
}

class _SuperAdminTileStyle {
  final String name;
  final String url;
  final List<String> subdomains;
  final int maxZoom;

  const _SuperAdminTileStyle({
    required this.name,
    required this.url,
    this.subdomains = const [],
    this.maxZoom = 19,
  });
}

class DashboardSuperAdminPage extends StatefulWidget {
  const DashboardSuperAdminPage({super.key});

  @override
  State<DashboardSuperAdminPage> createState() =>
      _DashboardSuperAdminPageState();
}

class _DashboardSuperAdminPageState extends State<DashboardSuperAdminPage> {
  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  final MapController _mapController = MapController();

  int _selectedTileStyle = 0;

static const List<_SuperAdminTileStyle> _tileStyles = [
  _SuperAdminTileStyle(
    name: 'Plan',
    url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    maxZoom: 19,
  ),
  _SuperAdminTileStyle(
    name: 'Satellite',
    url:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    maxZoom: 19,
  ),
  _SuperAdminTileStyle(
    name: 'Relief',
    url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
    maxZoom: 17,
  ),
];

  Map<String, dynamic>? _selectedSpot;

  Map<String, dynamic>? _selectedAdmin;

  Map<String, dynamic>? _selectedAdvertiser;

  bool _showLegalDocumentsPanel = false;

  String? _selectedLegalDocument;
  String? _selectedLegalChapter;

  final TextEditingController _legalTitleController = TextEditingController();
  final TextEditingController _legalContentController = TextEditingController();
  final TextEditingController _legalVersionController = TextEditingController();
  final TextEditingController _legalPublicationDateController = TextEditingController();
  final TextEditingController _legalChangeLogController = TextEditingController();
  final Set<String> _modifiedDocuments = {};

final Map<String, List<String>> _documentChapters = {
  'CGU': [],
  'Politique de confidentialité': [],
  'RGPD': [],
};

final Map<String, Set<String>> _modifiedChapters = {
  'CGU': {},
  'Politique de confidentialité': {},
  'RGPD': {},
};

  String _selectedVersionDocument = 'CGU';
  String _selectedLegalStatus = 'Publié';
  String _legalLastUpdatedText = 'Non renseignée';

  bool _legalVersionSaved = false;
  bool _legalVersionButtonRed = false;
  bool _isSavingLegalVersion = false;

  bool _isSavingLegalChapter = false;
  bool _isLoadingLegalChapter = false;
  
int _visibleAdvertiserCount = 0;

final GlobalKey _advertiserFiltersKey = GlobalKey();
final GlobalKey _legalStatusKey = GlobalKey();

DashboardAdvertiserFilter _selectedAdvertiserFilter =
    DashboardAdvertiserFilter.pending;

  final TextEditingController _searchController = TextEditingController();
String _searchText = '';

List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestSpotDocs = [];

List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestAdminDocs = [];

List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestAdDocs = [];

Map<String, Map<String, dynamic>> _subscriptionsByUid = {};

late stt.SpeechToText _speech;
bool _isListening = false;

  int _visibleOnMapSpotCount = 0;
  int _visibleOnMapAdminCount = 0;
  int _visibleOnMapSauveteurCount = 0;
  int _sauveteurCountRequestId = 0;

  OverlayEntry? _dropdownOverlay;

  final GlobalKey _filtersKey = GlobalKey();
  final GlobalKey _adminFiltersKey = GlobalKey();

  final Set<DashboardSpotFilter> _selectedFilters = {
    DashboardSpotFilter.all,
  };

  DashboardAdminFilter _selectedAdminFilter =
      DashboardAdminFilter.all;

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> get _spotsStream async* {
  await for (final territoiresSnapshot
      in FirebaseFirestore.instance.collection('territoires').snapshots()) {
    final allSpots = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (final territoireDoc in territoiresSnapshot.docs) {
      final spotsSnapshot = await territoireDoc.reference
          .collection('spots')
          .get();

      allSpots.addAll(spotsSnapshot.docs);
    }

    yield allSpots;
  }
}

  Stream<QuerySnapshot<Map<String, dynamic>>> get _adminRequestsStream {
  return FirebaseFirestore.instance
      .collection('adminRequests')
      .snapshots();
}

Stream<QuerySnapshot<Map<String, dynamic>>> get _subscriptionsStream {
  return FirebaseFirestore.instance
      .collection('subscriptions')
      .snapshots();
}

Stream<QuerySnapshot<Map<String, dynamic>>> get _adRequestsStream {
  return FirebaseFirestore.instance.collection('adRequests').snapshots();
}

Stream<QuerySnapshot<Map<String, dynamic>>> get _sauveteursStream {
  return FirebaseFirestore.instance
      .collection('sauveteurs')
      .snapshots();
}

Stream<DocumentSnapshot<Map<String, dynamic>>> _subscriptionStream(String uid) {
  return FirebaseFirestore.instance
      .collection('subscriptions')
      .doc(uid)
      .snapshots();
}

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  double _distanceKm(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadius = 6371.0;

  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;

  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);

  final c = 2 * math.atan2(
    math.sqrt(a),
    math.sqrt(1 - a),
  );

  return earthRadius * c;
}

String _cleanText(dynamic value) {
  return (value ?? '').toString().trim();
}

String _spotName(Map<String, dynamic> data) {
  return _cleanText(
    data['nomSphot'] ??
        data['nomSecours'] ??
        data['name'] ??
        data['nom'] ??
        data['title'] ??
        'SPHOT sans nom',
  );
}

String _normalizeType(String value) {
  return value
      .toUpperCase()
      .replaceAll('É', 'E')
      .replaceAll('È', 'E')
      .replaceAll('Ê', 'E')
      .replaceAll('À', 'A')
      .replaceAll('Â', 'A')
      .replaceAll('Î', 'I')
      .replaceAll('Ô', 'O')
      .replaceAll('Ù', 'U')
      .replaceAll('Û', 'U')
      .replaceAll('Ç', 'C')
      .trim();
}

String _getMarkerIconPath(Map<String, dynamic> data) {
  final type = _normalizeType((data['typeSphot'] ?? '').toString());
  final nature = _normalizeType((data['natureSphot'] ?? '').toString());
  final label = _normalizeType((data['labelSphot'] ?? '').toString());

  final fullType = '$type $nature $label';

  if (fullType.contains('NATURISME')) {
    return 'data/icons/fire_skin_icon.png';
  }

  if (fullType.contains('POSTE DE SECOURS')) {
    return 'data/icons/fire_red_icon.png';
  }

  if (fullType.contains('ACCES PLAGE')) {
    return 'data/icons/fire_orange_icon.png';
  }

  if (fullType.contains('LAC') ||
      fullType.contains("PLAN D'EAU") ||
      fullType.contains('PLAN D EAU') ||
      fullType.contains('BARRAGE')) {
    return 'data/icons/fire_blue_icon.png';
  }

  if (fullType.contains('FLEUVE') || fullType.contains('RIVIERE')) {
    return 'data/icons/fire_green_icon.png';
  }

  if (fullType.contains('LAGON') || fullType.contains('PISCINE NATURELLE')) {
    return 'data/icons/fire_cyan_icon.png';
  }

  return 'data/icons/fire_orange1_icon.png';
}

Color _spotTypeColor(Map<String, dynamic> data) {
  final type = _normalizeType((data['typeSphot'] ?? '').toString());
  final nature = _normalizeType((data['natureSphot'] ?? '').toString());
  final label = _normalizeType((data['labelSphot'] ?? '').toString());

  final fullType = '$type $nature $label';

  if (fullType.contains('POSTE DE SECOURS')) {
    return const Color(0xFFFF0000);
  }

  if (fullType.contains('NATURISME')) {
    return const Color(0xFFD87A5C);
  }

  if (fullType.contains('ACCES PLAGE') || fullType.contains('ACCÈS PLAGE')) {
    return const Color(0xFFFFD000);
  }

  if (fullType.contains('LAC') ||
      fullType.contains("PLAN D'EAU") ||
      fullType.contains('PLAN D EAU') ||
      fullType.contains('BARRAGE')) {
    return const Color(0xFF1E3A8A);
  }

  if (fullType.contains('FLEUVE') || fullType.contains('RIVIERE')) {
    return const Color(0xFF2E7D32);
  }

  if (fullType.contains('LAGON') || fullType.contains('PISCINE NATURELLE')) {
    return const Color(0xFF00ACC1);
  }

  return const Color(0xFFFFA500);
}

bool _matchesFilter(Map<String, dynamic> data) {
  if (_selectedFilters.contains(DashboardSpotFilter.none)) {
  return false;
}
  if (_selectedFilters.contains(DashboardSpotFilter.all)) {
    return true;
  }

  return _selectedFilters.any((filter) {
    final previous = _selectedFilters;
    switch (filter) {
  case DashboardSpotFilter.none:
    return false;
  case DashboardSpotFilter.all:
    return true;
  case DashboardSpotFilter.secours:
    return _matchesFilterType(data, DashboardSpotFilter.secours);
  case DashboardSpotFilter.eauVerte:
    return _matchesFilterType(data, DashboardSpotFilter.eauVerte);
  case DashboardSpotFilter.lagon:
    return _matchesFilterType(data, DashboardSpotFilter.lagon);
  case DashboardSpotFilter.eauBleue:
    return _matchesFilterType(data, DashboardSpotFilter.eauBleue);
  case DashboardSpotFilter.plage:
    return _matchesFilterType(data, DashboardSpotFilter.plage);
  case DashboardSpotFilter.naturisme:
    return _matchesFilterType(data, DashboardSpotFilter.naturisme);
  case DashboardSpotFilter.loisirs:
    return _matchesFilterType(data, DashboardSpotFilter.loisirs);
}
  });
}

bool _matchesFilterType(
  Map<String, dynamic> data,
  DashboardSpotFilter filter,
) {
  final type = _normalizeType((data['typeSphot'] ?? '').toString());
  final nature = _normalizeType((data['natureSphot'] ?? '').toString());
  final label = _normalizeType((data['labelSphot'] ?? '').toString());
  final fullType = '$type $nature $label';

  switch (filter) {
    case DashboardSpotFilter.all:
      return true;

    case DashboardSpotFilter.none:
  return false;  

    case DashboardSpotFilter.secours:
      return fullType.contains('POSTE DE SECOURS');

    case DashboardSpotFilter.eauVerte:
      return fullType.contains('FLEUVE') ||
          fullType.contains('RIVIERE');

    case DashboardSpotFilter.lagon:
      return fullType.contains('LAGON') ||
          fullType.contains('PISCINE NATURELLE');

    case DashboardSpotFilter.eauBleue:
      return fullType.contains('LAC') ||
          fullType.contains("PLAN D'EAU") ||
          fullType.contains('PLAN D EAU') ||
          fullType.contains('BARRAGE');

    case DashboardSpotFilter.plage:
      return fullType.contains('PLAGE') ||
          fullType.contains('ACCES PLAGE');

    case DashboardSpotFilter.naturisme:
      return fullType.contains('NATURISME');

    case DashboardSpotFilter.loisirs:
      return fullType.contains('BASE DE LOISIRS') ||
          fullType.contains('PARC');
  }
}

String _filterLabel(DashboardSpotFilter filter) {
  switch (filter) {
    case DashboardSpotFilter.none:
  return 'Aucun';
    case DashboardSpotFilter.all:
      return 'Tous les SPHOTS';
    case DashboardSpotFilter.secours:
      return 'Poste de secours';
    case DashboardSpotFilter.eauVerte:
      return 'Fleuve\nRivière';
    case DashboardSpotFilter.lagon:
      return 'Lagon\nPiscine naturelle';
    case DashboardSpotFilter.eauBleue:
      return "Lac\nPlan d'eau\nBarrage";
    case DashboardSpotFilter.plage:
      return 'Plage';
    case DashboardSpotFilter.naturisme:
      return 'Naturisme';
    case DashboardSpotFilter.loisirs:
      return 'Base de loisirs\nParc';
  }
}

Color _filterColor(DashboardSpotFilter filter) {
  switch (filter) {
    case DashboardSpotFilter.none:
  return Colors.grey;
    case DashboardSpotFilter.all:
      return adminColor;
    case DashboardSpotFilter.secours:
      return const Color(0xFFFF0000);
    case DashboardSpotFilter.plage:
      return const Color(0xFFFFD000);
    case DashboardSpotFilter.eauBleue:
      return const Color(0xFF1E3A8A);
    case DashboardSpotFilter.eauVerte:
      return const Color(0xFF2E7D32);
    case DashboardSpotFilter.lagon:
      return const Color(0xFF00ACC1);
    case DashboardSpotFilter.naturisme:
      return const Color(0xFFD87A5C);
    case DashboardSpotFilter.loisirs:
  return const Color(0xFFFFA500);
  }
}

Widget _buildFiltersBlock() {
  final displayText = _selectedFilters.contains(DashboardSpotFilter.all)
      ? 'Tous les SPHOTS'
      : _selectedFilters.map(_filterLabel).join(' | ');

  return GestureDetector(
  key: _filtersKey,
  onTap: _openFiltersMenu,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: 'Filtres SPHOTS',
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
              displayText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: redColor,
              ),
            ),
          ),
          const Icon(
            Icons.checklist_rounded,
            color: redColor,
            size: 22,
          ),
          const SizedBox(width: 2),
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

Widget _buildAdminFiltersBlock() {
  final displayText = _adminFilterLabel(_selectedAdminFilter);

  return GestureDetector(
    key: _adminFiltersKey,
    onTap: _openAdminFiltersMenu,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: 'Filtres ADMIN',
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
          borderSide: const BorderSide(color: adminColor, width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: adminColor, width: 1.6),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: redColor,
              ),
            ),
          ),
          const Icon(Icons.checklist_rounded, color: redColor, size: 22),
          const SizedBox(width: 2),
          const Icon(Icons.keyboard_arrow_down_rounded, color: redColor, size: 26),
        ],
      ),
    ),
  );
}

void _openFiltersMenu() {
  _dropdownOverlay?.remove();
  _dropdownOverlay = null;

  final renderBox =
      _filtersKey.currentContext!.findRenderObject() as RenderBox;

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
                  onTap: () {
                    _dropdownOverlay?.remove();
                    _dropdownOverlay = null;
                  },
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
                    constraints: const BoxConstraints(maxHeight: 245),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.94),
                      border: const Border(
                        left: BorderSide(color: adminColor, width: 1.4),
                        right: BorderSide(color: adminColor, width: 1.4),
                        bottom: BorderSide(color: adminColor, width: 1.4),
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                    ),
                    child: Scrollbar(
                      controller: scrollController,
                      thumbVisibility: true,
                      thickness: 10,
                      radius: const Radius.circular(10),
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: DashboardSpotFilter.values.map((filter) {
                          final selected = _selectedFilters.contains(filter);

                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (filter == DashboardSpotFilter.none) {
                                  _selectedFilters
                                    ..clear()
                                    ..add(DashboardSpotFilter.none);
                                } else if (filter == DashboardSpotFilter.all) {
                                  _selectedFilters
                                    ..clear()
                                    ..add(DashboardSpotFilter.all);
                                } else {
                                  _selectedFilters.remove(DashboardSpotFilter.none);
                                  _selectedFilters.remove(DashboardSpotFilter.all);

                                  if (selected) {
                                    _selectedFilters.remove(filter);
                                  } else {
                                    _selectedFilters.add(filter);
                                  }

                                  if (_selectedFilters.isEmpty) {
                                    _selectedFilters.add(DashboardSpotFilter.all);
                                  }
                                }

                                _selectedSpot = null;
                                _selectedAdmin = null;
                              });

                              overlaySetState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    color: selected ? redColor : adminColor,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _filterLabel(filter),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: selected ? redColor : adminColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
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

void _openAdminFiltersMenu() {
  _dropdownOverlay?.remove();
  _dropdownOverlay = null;

  final renderBox =
      _adminFiltersKey.currentContext!.findRenderObject() as RenderBox;

  final position = renderBox.localToGlobal(Offset.zero);
  final size = renderBox.size;
  final scrollController = ScrollController();

  _dropdownOverlay = OverlayEntry(
    builder: (context) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _dropdownOverlay?.remove();
                _dropdownOverlay = null;
              },
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
                constraints: const BoxConstraints(maxHeight: 190),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.94),
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
    radius: Radius.circular(10),
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: DashboardAdminFilter.values.map((filter) {
                      final selected = _selectedAdminFilter == filter;

                      return InkWell(
                        onTap: () {
                          setState(() {
  _selectedAdminFilter = filter;
  _selectedSpot = null;
  _selectedAdmin = null;
});

                          _dropdownOverlay?.remove();
                          _dropdownOverlay = null;
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                color: selected ? redColor : adminColor,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _adminFilterLabel(filter),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: selected ? redColor : adminColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
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

Color _clusterBorderColor(List<Marker> markers) {
  final colors = <Color>{};

  for (final marker in markers) {
    final child = marker.child;

    if (child is DashboardSpotMarker) {
      colors.add(child.typeColor);
    }
  }

  if (colors.contains(const Color(0xFFFF0000))) {
    return const Color(0xFFFF0000);
  }

  if (colors.contains(const Color(0xFFD87A5C))) {
    return const Color(0xFFD87A5C);
  }

  if (colors.contains(const Color(0xFFFFD000))) {
    return const Color(0xFFFFD000);
  }

  if (colors.contains(const Color(0xFF1E3A8A))) {
    return const Color(0xFF1E3A8A);
  }

  if (colors.contains(const Color(0xFF2E7D32))) {
    return const Color(0xFF2E7D32);
  }

  if (colors.contains(const Color(0xFF00ACC1))) {
    return const Color(0xFF00ACC1);
  }

  return const Color(0xFFFFA500);
}

String _clusterIconPath(Color color) {
  if (color == const Color(0xFFFF0000)) {
    return 'data/icons/fire_red_icon.png';
  }

  if (color == const Color(0xFFD87A5C)) {
    return 'data/icons/fire_skin_icon.png';
  }

  if (color == const Color(0xFFFFD000)) {
    return 'data/icons/fire_orange_icon.png';
  }

  if (color == const Color(0xFF1E3A8A)) {
    return 'data/icons/fire_blue_icon.png';
  }

  if (color == const Color(0xFF2E7D32)) {
    return 'data/icons/fire_green_icon.png';
  }

  if (color == const Color(0xFF00ACC1)) {
    return 'data/icons/fire_cyan_icon.png';
  }

  return 'data/icons/fire_orange1_icon.png';
}

  Marker _buildSpotMarker(Map<String, dynamic> data) {
  final lat = _toDouble(data['sphotLat']);
  final lng = _toDouble(data['sphotLng']);
  final name = _spotName(data);
  final iconPath = _getMarkerIconPath(data);

  return Marker(
    point: LatLng(lat, lng),
    width: 90,
    height: 90,
    alignment: Alignment.center,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _selectedSpot = data;
          _selectedAdmin = null;
          _selectedAdvertiser = null;
          _showLegalDocumentsPanel = false;
        });

        _mapController.move(
          LatLng(lat, lng),
          18,
        );
      },
      child: Center(
        child: DashboardSpotMarker(
          data: data,
          name: name,
          iconPath: iconPath,
          typeColor: _spotTypeColor(data),
        ),
      ),
    ),
  );
}

Widget _selectedSpotCard() {
  final spot = _selectedSpot;

  if (spot == null) {
    return Container(
  width: double.infinity,
  height: double.infinity,
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  decoration: BoxDecoration(
    color: Colors.grey.withOpacity(0.10),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.grey.withOpacity(0.25)),
  ),
  child: const Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.tune, size: 18, color: Colors.grey),
      SizedBox(width: 8),
      Expanded(
        child: Text(
          'Cliquez sur un SPHOT pour afficher ses informations',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ),
    ],
  ),
);
  }

  final name = _spotName(spot);
  final type = _cleanText(spot['typeSphot'] ?? 'Type non renseigné');
final ville = _cleanText(spot['ville'] ?? 'Ville non renseignée');
final departement = _cleanText(
  spot['departement'] ?? 'Département non renseigné',
);
  final telephone = _cleanText(
  spot['telephonePoste'] ?? 'Non renseigné',
);

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _spotTypeColor(spot).withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: _spotTypeColor(spot),
        width: 1.5,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
  name,
  maxLines: 3,
  softWrap: true,
  overflow: TextOverflow.fade,
  style: TextStyle(
  color: _spotTypeColor(spot),
  fontSize: 17,
  fontWeight: FontWeight.w900,
  height: 1.15,
),
),
        const SizedBox(height: 10),
        _spotInfoLine('Type', type),
_spotInfoLine('Ville', ville),
_spotInfoLine('Département', departement),

if (_normalizeType(type).contains('POSTE DE SECOURS'))
  _spotInfoLine('Téléphone', telephone),
      ],
    ),
  );
}

Widget _spotInfoLine(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 95,
          child: Text(
            '$label :',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.black87,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

String _adminFilterLabel(DashboardAdminFilter filter) {
  switch (filter) {
    case DashboardAdminFilter.none:
  return 'Aucun';
    case DashboardAdminFilter.all:
      return 'Toutes';
    case DashboardAdminFilter.trial:
      return 'En essai';
    case DashboardAdminFilter.active:
      return 'Actives';
    case DashboardAdminFilter.overdue:
      return 'En retard';
    case DashboardAdminFilter.cancelled:
      return 'Résiliées';
  }
}

bool _matchesAdminFilter(Map<String, dynamic> data) {
  if (_selectedAdminFilter == DashboardAdminFilter.none) {
  return false;
}
  if (_selectedAdminFilter == DashboardAdminFilter.all) {
    return true;
  }

  final uid = _cleanText(data['uid']);
  final subscription = _subscriptionsByUid[uid];

  if (subscription == null) {
    return false;
  }

  final status = _cleanText(subscription['status']);

  switch (_selectedAdminFilter) {
    case DashboardAdminFilter.none:
      return false;
    case DashboardAdminFilter.all:
      return true;
    case DashboardAdminFilter.trial:
      return status == 'trial';
    case DashboardAdminFilter.active:
      return status == 'active';
    case DashboardAdminFilter.overdue:
      return status == 'overdue';
    case DashboardAdminFilter.cancelled:
      return status == 'cancelled';
  }
}

String _formatDate(dynamic value) {
  if (value == null) return 'Non renseignée';

  if (value is Timestamp) {
    final date = value.toDate();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  return value.toString();
}

Widget _selectedAdminCard() {
  final admin = _selectedAdmin;
  if (admin == null) return const SizedBox.shrink();

  final uid = _cleanText(admin['uid']);
  final territoire = Map<String, dynamic>.from(admin['territoire'] ?? {});
  final structure = Map<String, dynamic>.from(admin['structure'] ?? {});
  final profile = Map<String, dynamic>.from(admin['profile'] ?? {});

  final mairie = _cleanText(
    structure['nom'] ?? admin['nomStructure'] ?? 'ADMIN',
  );

  final email = _cleanText(profile['email'] ?? admin['email']);
  final siret = _cleanText(structure['siret'] ?? admin['siret']);
  final ville = _cleanText(territoire['ville']);
  final departement = _cleanText(territoire['departement']);

  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    future: FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(uid)
        .get(),
    builder: (context, snapshot) {
      final subscription = snapshot.data?.data() ?? {};

      final status = _cleanText(subscription['status'] ?? admin['status']);

      final trialStart = subscription['trialStartDate'];
      final trialEnd = subscription['trialEndDate'];
      final subscriptionStart = subscription['subscriptionStartDate'];
      final subscriptionEnd = subscription['subscriptionEndDate'];

      final numberOfSpots =
          _toDouble(subscription['numberOfRescueStations']).toInt();

      final pricePerSpot =
          _toDouble(subscription['pricePerStationExclTax']);

      final totalPrice = numberOfSpots * pricePerSpot;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: adminColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: adminColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mairie,
              style: const TextStyle(
                color: adminColor,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),

            _spotInfoLine(
  'Responsable',
  _cleanText(
    profile['nomAffiche'] ??
    admin['nomResponsable'] ??
    admin['prenom'] ??
    '',
  ),
),
_spotInfoLine('Email', email),
_spotInfoLine('Statut', status),
            _spotInfoLine('Date départ', _formatDate(trialStart ?? subscriptionStart)),
            _spotInfoLine('Date fin', _formatDate(trialEnd ?? subscriptionEnd)),
            _spotInfoLine('SPHOTS', '$numberOfSpots'),
            _spotInfoLine(
              'Coût',
              '${totalPrice.toStringAsFixed(0)} € HT / an',
            ),
            
          ],
        ),
      );
    },
  );
}

Widget _buildRightPanel({
  required int visibleSpots,
}) {
  return Container(
    width: 360,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.96),
      border: Border(
        right: BorderSide(
          color: adminColor.withOpacity(0.25),
          width: 1.5,
        ),
      ),
    ),
    child: SafeArea(
  child: Padding(
    padding: const EdgeInsets.all(22),
      child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
            _summaryCard(
              title: 'SPHOTS',
              value: '$_visibleOnMapSpotCount',
              color: adminColor,
            ),
            const SizedBox(height: 18),
            _buildFiltersBlock(),

            const SizedBox(height: 24),

            _summaryCard(
  title: 'ADMINS',
  value: '$_visibleOnMapAdminCount',
  color: adminColor,
),
const SizedBox(height: 18),
_buildAdminFiltersBlock(),

const SizedBox(height: 24),

_summaryCard(
  title: 'ANNONCEURS',
  value: '$_visibleAdvertiserCount',
  color: adminColor,
),
const SizedBox(height: 18),
_buildAdvertiserFiltersBlock(),

const SizedBox(height: 24),

_summaryCard(
  title: 'SAUVETEURS',
  value: '$_visibleOnMapSauveteurCount',
  color: adminColor,
),

const SizedBox(height: 14),

GestureDetector(
  onTap: () {
    setState(() {
      _showLegalDocumentsPanel = true;
      _selectedSpot = null;
      _selectedAdmin = null;
      _selectedAdvertiser = null;
    });
  },
  child: Container(
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: (_showLegalDocumentsPanel ? redColor : adminColor).withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: _showLegalDocumentsPanel ? redColor : adminColor,
        width: 1.5,
      ),
    ),
    child: Row(
      children: [
        Image.asset(
          'data/icons/fire_blue_icon.png',
          width: 30,
          height: 30,
          filterQuality: FilterQuality.high,
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            'DOCUMENTS JURIDIQUES',
            style: TextStyle(
              color: adminColor,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  ),
),

            
                    ],
        ),
          ),
    ),
  );
}

  Widget _summaryCard({
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
  height: 80,
  padding: const EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 8,
  ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        children: [
          Image.asset(
  'data/icons/fire_blue_icon.png',
  width: 34,
  height: 34,
  filterQuality: FilterQuality.high,
),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
  mainAxisSize: MainAxisSize.min,
  mainAxisAlignment: MainAxisAlignment.center,
  crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _comingSoon(String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

String _advertiserFilterLabel(DashboardAdvertiserFilter filter) {
  switch (filter) {
    case DashboardAdvertiserFilter.none:
      return 'Aucun';

    case DashboardAdvertiserFilter.pending:
      return 'En attente';

    case DashboardAdvertiserFilter.all:
      return 'Tous';

    case DashboardAdvertiserFilter.active:
      return 'Actifs';

    case DashboardAdvertiserFilter.expiringSoon:
      return 'Expirant sous 7 jours';

    case DashboardAdvertiserFilter.finished:
      return 'Terminés';
  }
}

Widget _buildAdvertiserFiltersBlock() {
  final displayText = _advertiserFilterLabel(_selectedAdvertiserFilter);

  return GestureDetector(
    key: _advertiserFiltersKey,
    onTap: _openAdvertiserFiltersMenu,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: 'Filtres ANNONCEURS',
        labelStyle: const TextStyle(
          color: adminColor,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: adminColor, width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: adminColor, width: 1.6),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayText,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: redColor,
              ),
            ),
          ),
          const Icon(
  Icons.checklist_rounded,
  color: redColor,
  size: 22,
),
          const SizedBox(width: 2),
          const Icon(Icons.keyboard_arrow_down_rounded, color: redColor, size: 26),
        ],
      ),
    ),
  );
}

void _openAdvertiserFiltersMenu() {
  _dropdownOverlay?.remove();
  _dropdownOverlay = null;

  final renderBox =
      _advertiserFiltersKey.currentContext!.findRenderObject() as RenderBox;

  final position = renderBox.localToGlobal(Offset.zero);
  final size = renderBox.size;

  _dropdownOverlay = OverlayEntry(
    builder: (context) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _dropdownOverlay?.remove();
                _dropdownOverlay = null;
              },
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
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.94),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: DashboardAdvertiserFilter.values.map((filter) {
                    final selected = _selectedAdvertiserFilter == filter;

                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedAdvertiserFilter = filter;
                          _selectedSpot = null;
                          _selectedAdmin = null;
                          _selectedAdvertiser = null;
                        });

                        _dropdownOverlay?.remove();
                        _dropdownOverlay = null;
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: selected ? redColor : adminColor,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _advertiserFilterLabel(filter),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: selected ? redColor : adminColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
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

bool _matchesAdvertiserFilter(Map<String, dynamic> data) {
  final status = _cleanText(data['status']).toLowerCase();

  if (_selectedAdvertiserFilter == DashboardAdvertiserFilter.none) {
  return false;
}

  switch (_selectedAdvertiserFilter) {
    case DashboardAdvertiserFilter.none:
      return false;

    case DashboardAdvertiserFilter.pending:
      return status == 'pending';

    case DashboardAdvertiserFilter.all:
      return true;

    case DashboardAdvertiserFilter.active:
      return status == 'active';

    case DashboardAdvertiserFilter.expiringSoon:
      final endDate = data['campaignEndDate'];
      if (endDate is! Timestamp) return false;

      final now = DateTime.now();
      final limit = now.add(const Duration(days: 7));
      final date = endDate.toDate();

      return date.isAfter(now) && date.isBefore(limit);

    case DashboardAdvertiserFilter.finished:
      final endDate = data['campaignEndDate'];
      if (endDate is! Timestamp) return false;

      return endDate.toDate().isBefore(DateTime.now());
  }
}

bool _matchesAdvertiserSearch(Map<String, dynamic> data) {
  final query = _normalizeSearch(_searchText);
  if (query.isEmpty) return true;

  final fields = [
  data['advertiserName'],
  data['contactName'],
  data['email'],
  data['phone'],
  data['siret'],
  data['city'],
  data['department'],
  data['region'],
  data['status'],
  data['broadcastType'],
  data['visibilityLabel'],
  data['campaignTitle'],
  data['companyName'],
  data['businessName'],
  data['organisation'],
].map((value) => _normalizeSearch((value ?? '').toString())).toList();

  return fields.any((field) => field.contains(query) || query.contains(field));
}

Widget _buildSpotDetailPanel() {
  final spot = _selectedSpot;
  if (spot == null) return const SizedBox.shrink();

  final name = _spotName(spot);
  final type = _cleanText(spot['typeSphot'] ?? 'Non renseigné');
  final nature = _cleanText(spot['natureSphot'] ?? 'Non renseignée');
  final label = _cleanText(spot['labelSphot'] ?? 'Non renseigné');
  final ville = _cleanText(spot['ville'] ?? 'Non renseignée');
  final departement = _cleanText(spot['departement'] ?? 'Non renseigné');
  final region = _cleanText(spot['region'] ?? 'Non renseignée');
  final telephone = _cleanText(spot['telephonePoste'] ?? 'Non renseigné');
  final lat = _toDouble(spot['sphotLat']);
  final lng = _toDouble(spot['sphotLng']);

  return Container(
    width: 420,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.98),
      border: Border(
        left: BorderSide(
          color: _spotTypeColor(spot).withOpacity(0.45),
          width: 1.5,
        ),
      ),
    ),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: _spotTypeColor(spot),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedSpot = null;
                    });
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),

            _spotInfoLine('Type', type),
            _spotInfoLine('Nature', nature),
            _spotInfoLine('Label', label),
            _spotInfoLine('Ville', ville),
            _spotInfoLine('Département', departement),
            _spotInfoLine('Région', region),
            _spotInfoLine('Téléphone', telephone),
            _spotInfoLine('Latitude', lat.toStringAsFixed(6)),
            _spotInfoLine('Longitude', lng.toStringAsFixed(6)),
          ],
        ),
      ),
    ),
  );
}

Widget _buildAdvertiserDetailPanel() {
  final advertiser = _selectedAdvertiser;
  if (advertiser == null) return const SizedBox.shrink();

  final companyName = _cleanText(
  advertiser['advertiserName'] ??
      advertiser['companyName'] ??
      advertiser['businessName'] ??
      advertiser['organisation'] ??
      'Annonceur',
);

  final email = _cleanText(advertiser['email'] ?? 'Non renseigné');
  final phone = _cleanText(advertiser['phone'] ?? 'Non renseigné');
  final websiteUrl = _cleanText(
  advertiser['websiteUrl'] ?? 'Non renseigné',
);

final siret = _cleanText(
  advertiser['siret'] ?? 'Non renseigné',
);

final siren = _cleanText(
  advertiser['siren'] ?? 'Non renseigné',
);

final categoryLabel = _cleanText(
  advertiser['categoryLabel'] ?? 'Non renseignée',
);

final durationLabel = _cleanText(
  advertiser['durationLabel'] ?? 'Non renseignée',
);
  final rawStatus = _cleanText(
  advertiser['status'] ?? '',
);

final campaignStatus = switch (rawStatus.toLowerCase()) {
  'pending' => 'En attente de validation',
  'active' => 'Active',
  'approved' => 'Approuvée',
  'rejected' => 'Refusée',
  'disabled' => 'Désactivée',
  'deleted' => 'Supprimée',
  'finished' => 'Terminée',
  _ => 'Non renseigné',
};
  final isApproved = rawStatus.toLowerCase() == 'approved';
final isRejected = rawStatus.toLowerCase() == 'rejected';
  final contactName = _cleanText(
  advertiser['contactName'] ?? 'Non renseigné',
);

final offerLabel = _cleanText(
  advertiser['visibilityLabel'] ?? 'Non renseignée',
);

final targetCity = _cleanText(
  advertiser['centerCity'] ?? 'Non renseignée',
);

final radiusLabel = advertiser['radiusKm'] != null
    ? '${advertiser['radiusKm']} km'
    : advertiser['broadcastType'] == 'national'
        ? 'National'
        : 'Non renseigné';

final radiusKm = _toDouble(advertiser['radiusKm']);
final centerLat = _toDouble(advertiser['centerLat']);
final centerLng = _toDouble(advertiser['centerLng']);

int coveredSpots = 0;

if (radiusKm > 0) {
  for (final doc in _latestSpotDocs) {
    final data = doc.data();

    final lat = _toDouble(data['sphotLat']);
    final lng = _toDouble(data['sphotLng']);

    if (lat == 0 || lng == 0) continue;

    final distance = _distanceKm(
      centerLat,
      centerLng,
      lat,
      lng,
    );

    if (distance <= radiusKm) {
      coveredSpots++;
    }
  }
}        

final price = _toDouble(
  advertiser['totalPriceExclTax'] ?? advertiser['priceExclTax'],
);

final bannerUrl = _cleanText(
  advertiser['bannerUrl'] ?? advertiser['imageUrl'],
);

  return Container(
    width: 420,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.98),
      border: Border(
        left: BorderSide(
          color: adminColor.withOpacity(0.25),
          width: 1.5,
        ),
      ),
    ),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
  children: [
    Expanded(
      child: Text(
        companyName,
        style: const TextStyle(
          color: adminColor,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
                    
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedAdvertiser = null;
                    });
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),

            if (bannerUrl.isNotEmpty)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  launchUrl(
                    Uri.parse(bannerUrl),
                    webOnlyWindowName: '_blank',
                  );
                },
                child: Container(
                  width: double.infinity,
                  height: 58,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: adminColor.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: adminColor.withOpacity(0.25),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.image_rounded, color: adminColor, size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Bannière publicitaire',
                          style: TextStyle(
                            color: adminColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.open_in_full_rounded,
                        color: adminColor,
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 18),

_spotInfoLine('Responsable', contactName),
_spotInfoLine('Email', email),
_spotInfoLine('Téléphone', phone),
_spotInfoLine('Site internet', websiteUrl.isEmpty ? 'Non renseigné' : websiteUrl),
_spotInfoLine('SIRET', siret.isEmpty ? 'Non renseigné' : siret),
_spotInfoLine('SIREN', siren.isEmpty ? 'Non renseigné' : siren),
_spotInfoLine('Catégorie', categoryLabel.isEmpty ? 'Non renseignée' : categoryLabel),
_spotInfoLine('Durée', durationLabel.isEmpty ? 'Non renseignée' : durationLabel),
_spotInfoLine('Ville cible', targetCity),
_spotInfoLine('Rayon d’action', radiusLabel),
_spotInfoLine('SPHOTS', '$coveredSpots touchés'),
_spotInfoLine('Offre choisie', offerLabel),
_spotInfoLine('Statut', campaignStatus),
_spotInfoLine('Début', _formatDate(advertiser['campaignStartDate'])),
_spotInfoLine('Fin', _formatDate(advertiser['campaignEndDate'])),
_spotInfoLine('Prix', '${price.toStringAsFixed(0)} € HT'),

            const SizedBox(height: 22),

            Row(
  children: [
    Expanded(
      child: ElevatedButton.icon(
        onPressed: () {
          setState(() {
            _selectedAdvertiser = {
              ...advertiser,
              'status': 'approved',
            };
          });
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isApproved ? redColor : adminColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: Icon(
          isApproved ? Icons.check_circle_rounded : Icons.check_rounded,
        ),
        label: Text(isApproved ? 'Approuvé' : 'Approuver'),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: ElevatedButton.icon(
        onPressed: () {
          setState(() {
            _selectedAdvertiser = {
              ...advertiser,
              'status': 'rejected',
            };
          });
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: isRejected ? redColor : adminColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: Icon(
          isRejected ? Icons.cancel_rounded : Icons.close_rounded,
        ),
        label: Text(isRejected ? 'Refusé' : 'Refuser'),
      ),
    ),
  ],
),
          ],
        ),
      ),
    ),
  );
}

Widget _buildAdminDetailPanel() {
  final admin = _selectedAdmin;
  if (admin == null) return const SizedBox.shrink();

  final uid = _cleanText(admin['uid']);
  final territoire = Map<String, dynamic>.from(admin['territoire'] ?? {});
  final structure = Map<String, dynamic>.from(admin['structure'] ?? {});
  final profile = Map<String, dynamic>.from(admin['profile'] ?? {});

  final mairie = _cleanText(
    structure['nom'] ?? admin['nomStructure'] ?? admin['organisation'] ?? 'ADMIN',
  );

  final email = _cleanText(profile['email'] ?? admin['email']);
  final responsable = _cleanText(
    profile['nomAffiche'] ??
        admin['nomResponsable'] ??
        '${admin['prenom'] ?? ''} ${admin['nom'] ?? ''}',
  );

  final siret = _cleanText(structure['siret'] ?? admin['siret']);
  final ville = _cleanText(territoire['ville']);
  final departement = _cleanText(territoire['departement']);
  final region = _cleanText(territoire['region']);
  final telephone = _cleanText(profile['telephone'] ?? admin['telephone']);

final rawStatus = _cleanText(admin['status'] ?? '');

final adminStatus = switch (rawStatus.toLowerCase()) {
  'pending' => 'En attente de validation',
  'approved' => 'Approuvé',
  'rejected' => 'Refusé',
  'active' => 'Actif',
  'trial' => 'Période d\'essai',
  'overdue' => 'En retard',
  'cancelled' => 'Résilié',
  _ => 'Non renseigné',
};
  return Container(
    width: 420,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.98),
      border: Border(
        left: BorderSide(
          color: adminColor.withOpacity(0.25),
          width: 1.5,
        ),
      ),
    ),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    mairie,
                    style: const TextStyle(
                      color: adminColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedAdmin = null;
                    });
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),

            _spotInfoLine('Responsable', responsable),
            _spotInfoLine('Email', email),
            _spotInfoLine('Téléphone', telephone.isEmpty ? 'Non renseigné' : telephone),
            _spotInfoLine('Organisation', mairie),
            _spotInfoLine('SIRET', siret.isEmpty ? 'Non renseigné' : siret),
            _spotInfoLine('Ville', ville),
            _spotInfoLine('Département', departement),
            _spotInfoLine('Région', region),
            _spotInfoLine('Statut', adminStatus),
          ],
        ),
      ),
    ),
  );
}

Widget _buildAdvertisersList() {
  return const SizedBox.shrink();
}

String _legalDocumentIdFromTitle(String title) {
  switch (title) {
    case 'CGU':
      return 'cgu';
    case 'Politique de confidentialité':
    case 'POLITIQUE DE CONFIDENTIALITÉ':
      return 'privacyPolicy';
    case 'RGPD':
      return 'rgpdNotice';
    default:
      return title;
  }
}

Future<List<String>> _loadLegalChaptersFromFirebase(String documentTitle) async {
  final documentId = _legalDocumentIdFromTitle(documentTitle);

  final snapshot = await FirebaseFirestore.instance
      .collection('legalDocuments')
      .doc(documentId)
      .collection('chapters')
      .orderBy(FieldPath.documentId)
      .get();

  return snapshot.docs.map((doc) {
    final data = doc.data();
    return (data['title'] ?? data['titre'] ?? doc.id).toString();
  }).toList();
}

Future<void> _loadAllLegalChaptersFromFirebase() async {
  final cgu = await _loadLegalChaptersFromFirebase('CGU');
  final privacy =
      await _loadLegalChaptersFromFirebase('Politique de confidentialité');
  final rgpd = await _loadLegalChaptersFromFirebase('RGPD');

  if (!mounted) return;

  setState(() {
    _documentChapters['CGU'] = cgu;
    _documentChapters['Politique de confidentialité'] = privacy;
    _documentChapters['RGPD'] = rgpd;
  });
}

Widget _buildLegalDocumentsPanel() {
  
  return Container(
    width: 420,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.98),
      border: Border(
        left: BorderSide(
          color: adminColor.withOpacity(0.25),
          width: 1.5,
        ),
      ),
    ),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'DOCUMENTS JURIDIQUES',
                    style: TextStyle(
                      color: adminColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _showLegalDocumentsPanel = false;
                      _selectedLegalDocument = null;
                      _selectedLegalChapter = null;
                    });
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),

            _legalDocumentTile(
  title: 'CGU',
  subtitle: 'Conditions Générales d’Utilisation',
  chapters: _documentChapters['CGU'] ?? [],
),

            const SizedBox(height: 12),

            _legalDocumentTile(
  title: 'POLITIQUE DE CONFIDENTIALITÉ',
  subtitle: 'Données personnelles et confidentialité',
  chapters: _documentChapters['Politique de confidentialité'] ?? [],
),

            const SizedBox(height: 12),

            _legalDocumentTile(
  title: 'RGPD',
  subtitle: 'Notice d’information RGPD',
  chapters: _documentChapters['RGPD'] ?? [],
),

const SizedBox(height: 12),

_buildLegalVersionTile(),

              ],
            ),
          
      ),
    ),
  );
}

Widget _buildLegalChapterEditor() {
  return Material(
    color: Colors.transparent,
    child: Container(
      margin: const EdgeInsets.only(top: 10, bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: adminColor, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _legalTitleController,
            decoration: InputDecoration(
              labelText: 'Titre du chapitre',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),

          const SizedBox(height: 14),

          TextField(
            controller: _legalContentController,
            minLines: 10,
            maxLines: 18,
            decoration: InputDecoration(
              labelText: 'Contenu du chapitre',
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isSavingLegalChapter ? null : _saveLegalChapter,
              icon: const Icon(Icons.save_rounded),
              label: const Text('ENREGISTRER'),
              style: ElevatedButton.styleFrom(
                backgroundColor: adminColor,
                foregroundColor: Colors.white,
              ),
            ),
                    ),
        ],
      ),
    ),
  );
}

Widget _modifiedChaptersBlock(String documentName) {
  if (!_modifiedDocuments.contains(documentName)) {
    return const SizedBox.shrink();
  }

  final chapters = _documentChapters[documentName] ?? [];

  if (chapters.isEmpty) {
    return const Padding(
      padding: EdgeInsets.only(left: 12, bottom: 10),
      child: Text(
        'Aucun chapitre disponible.',
        style: TextStyle(
          color: adminColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  return Padding(
    padding: const EdgeInsets.only(left: 12, bottom: 12),
    child: Column(
      children: chapters.map((chapter) {
        final selected =
            _modifiedChapters[documentName]?.contains(chapter) ?? false;

        return CheckboxListTile(
          value: selected,
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeColor: adminColor,
          title: Text(
            chapter,
            style: const TextStyle(
              color: adminColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          onChanged: (value) {
            setState(() {
              final set = _modifiedChapters[documentName] ?? <String>{};

              if (value == true) {
  set.add(chapter);
  _modifiedDocuments.add(documentName);
} else {
  set.remove(chapter);

  if (set.isEmpty) {
    _modifiedDocuments.remove(documentName);
  }
}

_modifiedChapters[documentName] = set;
            });
          },
        );
      }).toList(),
    ),
  );
}

bool get _canPublishVersion {
  if (_modifiedDocuments.isEmpty) return false;

  if (_legalChangeLogController.text.trim().isEmpty) {
    return false;
  }

  for (final document in _modifiedDocuments) {
    final selectedChapters = _modifiedChapters[document] ?? {};
    if (selectedChapters.isEmpty) {
      return false;
    }
  }

  return true;
}

Widget _buildLegalVersionsHistory() {
  return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
    future: FirebaseFirestore.instance
        .collection('legalVersions')
        .get(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'Erreur historique : ${snapshot.error}',
            style: const TextStyle(
              color: redColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      }

      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'Chargement de l’historique...',
            style: TextStyle(
              color: adminColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }

      final versions = snapshot.data!.docs;

      if (versions.isEmpty) {
        return const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'Aucune version enregistrée.',
            style: TextStyle(
              color: adminColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: versions.map((doc) {
          final data = doc.data();

          final version = (data['version'] ?? '').toString();
          final publicationDate =
              (data['publicationDate'] ?? 'Non renseignée').toString();
          final updatedAtText =
              (data['updatedAtText'] ?? 'Non renseignée').toString();
          final status = (data['status'] ?? 'Non renseigné').toString();
          final summary = (data['summary'] ??
                  data['changeLog'] ??
                  'Non renseigné')
              .toString();

          final documents =
              List<String>.from(data['documentsModified'] ?? []);

          final chaptersRaw =
              Map<String, dynamic>.from(data['chaptersModified'] ?? {});

          return Container(
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border.all(color: adminColor, width: 1.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ExpansionTile(
              iconColor: redColor,
              collapsedIconColor: redColor,
              title: Text(
                'Version $version',
                style: const TextStyle(
                  color: redColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(
                'Publiée le $publicationDate • MAJ $updatedAtText',
                style: const TextStyle(
                  color: adminColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              childrenPadding: const EdgeInsets.all(12),
              children: [
                _spotInfoLine('État', status),
                _spotInfoLine(
                  'Documents',
                  documents.isEmpty ? 'Non renseigné' : documents.join(', '),
                ),
                ...chaptersRaw.entries.map((entry) {
                  final chapters = List<String>.from(entry.value ?? []);
                  if (chapters.isEmpty) return const SizedBox.shrink();

                  return _spotInfoLine(entry.key, chapters.join(', '));
                }),
                _spotInfoLine('Résumé', summary),
              ],
            ),
          );
        }).toList(),
      );
    },
  );
}

Widget _buildLegalVersionTile() {
  return Container(
    decoration: BoxDecoration(
      color: adminColor.withOpacity(0.055),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: adminColor, width: 1.4),
    ),
    child: Material(
      color: Colors.transparent,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        iconColor: redColor,
        collapsedIconColor: redColor,
        title: const Text(
          'VERSION',
          style: TextStyle(
            color: redColor,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: const Text(
          'Version, publication et état du document',
          style: TextStyle(
            color: adminColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          TextField(
            controller: _legalVersionController,
            style: const TextStyle(
              color: redColor,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              labelText: 'Version',
              labelStyle: const TextStyle(
                color: adminColor,
                fontWeight: FontWeight.w700,
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
                borderSide: const BorderSide(color: adminColor, width: 1.8),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _legalPublicationDateController,
            readOnly: true,
            onTap: () async {
              final now = DateTime.now();

              final selectedDate = await showDatePicker(
                context: context,
                initialDate: now,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: adminColor,
                        onPrimary: Colors.white,
                        secondary: adminColor,
                        surface: Colors.white,
                        onSurface: Colors.black,
                      ),
                    ),
                    child: child!,
                  );
                },
              );

              if (selectedDate == null) return;

              _legalPublicationDateController.text =
                  '${selectedDate.day.toString().padLeft(2, '0')}/'
                  '${selectedDate.month.toString().padLeft(2, '0')}/'
                  '${selectedDate.year}';
            },
            style: const TextStyle(
              color: redColor,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              labelText: 'Date de publication',
              labelStyle: const TextStyle(
                color: adminColor,
                fontWeight: FontWeight.w700,
              ),
              suffixIcon: const Icon(
                Icons.calendar_month_rounded,
                color: redColor,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: adminColor, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: adminColor, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: adminColor, width: 1.8),
              ),
            ),
          ),
          const SizedBox(height: 12),

const SizedBox(height: 12),

const Text(
  'Documents modifiés',
  style: TextStyle(
    color: redColor,
    fontSize: 14,
    fontWeight: FontWeight.w900,
  ),
),

CheckboxListTile(
  value: _modifiedDocuments.contains('CGU'),
  onChanged: (value) {
    setState(() {
      if (value == true) {
        _modifiedDocuments.add('CGU');
      } else {
        _modifiedDocuments.remove('CGU');
        _modifiedChapters['CGU']?.clear();
      }
    });
  },
  title: const Text(
    'CGU',
    style: TextStyle(
      color: adminColor,
      fontWeight: FontWeight.w700,
      fontSize: 16,
    ),
  ),
  activeColor: adminColor,
  checkColor: Colors.white,
  side: const BorderSide(color: adminColor, width: 1.6),
),

_modifiedChaptersBlock('CGU'),

CheckboxListTile(
  value: _modifiedDocuments.contains('Politique de confidentialité'),
  onChanged: (value) {
    setState(() {
      if (value == true) {
        _modifiedDocuments.add('Politique de confidentialité');
      } else {
        _modifiedDocuments.remove('Politique de confidentialité');
        _modifiedChapters['Politique de confidentialité']?.clear();
      }
    });
  },
  title: const Text(
    'Politique de confidentialité',
    style: TextStyle(
      color: adminColor,
      fontWeight: FontWeight.w700,
      fontSize: 16,
    ),
  ),
  activeColor: adminColor,
  checkColor: Colors.white,
  side: const BorderSide(color: adminColor, width: 1.6),
),

_modifiedChaptersBlock('Politique de confidentialité'),

CheckboxListTile(
  value: _modifiedDocuments.contains('RGPD'),
  onChanged: (value) {
    setState(() {
      if (value == true) {
        _modifiedDocuments.add('RGPD');
      } else {
        _modifiedDocuments.remove('RGPD');
        _modifiedChapters['RGPD']?.clear();
      }
    });
  },
  title: const Text(
    'RGPD',
    style: TextStyle(
      color: adminColor,
      fontWeight: FontWeight.w700,
      fontSize: 16,
    ),
  ),
  activeColor: adminColor,
  checkColor: Colors.white,
  side: const BorderSide(color: adminColor, width: 1.6),
),

_modifiedChaptersBlock('RGPD'),

TextField(
  controller: _legalChangeLogController,
  minLines: 4,
  maxLines: 8,
  style: const TextStyle(
    color: adminColor,
    fontWeight: FontWeight.w700,
  ),
  decoration: InputDecoration(
    labelText: 'Résumé des modifications',
    alignLabelWithHint: true,
    labelStyle: const TextStyle(
      color: adminColor,
      fontWeight: FontWeight.w700,
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
      borderSide: const BorderSide(color: adminColor, width: 1.8),
    ),
  ),
),
          const SizedBox(height: 12),
          GestureDetector(
            key: _legalStatusKey,
            onTap: _openLegalStatusMenu,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'État',
                labelStyle: const TextStyle(
                  color: adminColor,
                  fontWeight: FontWeight.w700,
                ),
                filled: true,
                fillColor: Colors.transparent,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.6),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.6),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedLegalStatus,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: redColor,
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
          ),
          const SizedBox(height: 12),
          TextField(
            controller: TextEditingController(text: _legalLastUpdatedText),
            readOnly: true,
            style: const TextStyle(
              color: redColor,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              labelText: 'Dernière mise à jour',
              labelStyle: const TextStyle(
                color: adminColor,
                fontWeight: FontWeight.w700,
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
                borderSide: const BorderSide(color: adminColor, width: 1.8),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
  width: double.infinity,
  height: 46,
  child: ElevatedButton.icon(
    onPressed: _legalVersionButtonRed
    ? null
    : (_canPublishVersion ? _saveLegalVersionAndTurnButtonRed : null),
    icon: Icon(
      _legalVersionButtonRed
          ? Icons.check_circle_rounded
          : Icons.save_rounded,
    ),
    label: Text(
      _legalVersionButtonRed
          ? 'ENREGISTRÉE'
          : 'ENREGISTRER',
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: _legalVersionButtonRed
          ? redColor
          : adminColor,
      disabledBackgroundColor:
    _legalVersionButtonRed ? redColor : Colors.grey.shade300,
disabledForegroundColor:
    _legalVersionButtonRed ? Colors.white : Colors.grey,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(99),
      ),
    ),
  ),
),
const SizedBox(height: 16),

const Text(
  'Historique des versions',
  style: TextStyle(
    color: redColor,
    fontSize: 14,
    fontWeight: FontWeight.w900,
  ),
),

_buildLegalVersionsHistory(),
        ],
      ),
    ),
  );
}

Widget _legalDocumentTile({
  required String title,
  required String subtitle,
  required List<String> chapters,
}) {
  return Container(
    decoration: BoxDecoration(
      color: adminColor.withOpacity(0.055),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: adminColor, width: 1.4),
    ),
    child: Material(
      color: Colors.transparent,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        iconColor: redColor,
        collapsedIconColor: redColor,
        title: Text(
          title,
          style: const TextStyle(
            color: redColor,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: adminColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        children: chapters.map((chapter) {
          final isSelected =
              _selectedLegalDocument == title &&
              _selectedLegalChapter == chapter;

          return Column(
            children: [
              GestureDetector(
                onTap: () {
                  if (isSelected) {
                    setState(() {
                      _selectedLegalDocument = null;
                      _selectedLegalChapter = null;
                      _legalTitleController.clear();
                      _legalContentController.clear();
                    });
                  } else {
                    _loadLegalChapter(title, chapter);
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: adminColor.withOpacity(0.18),
                      ),
                    ),
                  ),
                  child: Text(
                    chapter,
                    style: const TextStyle(
                      color: adminColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (isSelected) _buildLegalChapterEditor(),
            ],
          );
        }).toList(),
      ),
    ),
  );
}

String _legalDocumentId(String title) {
  switch (title) {
    case 'CGU':
      return 'cgu';
    case 'POLITIQUE DE CONFIDENTIALITÉ':
      return 'privacyPolicy';
    case 'RGPD':
      return 'rgpdNotice';
    default:
      return 'cgu';
  }
}

String _legalChapterId(String chapter) {
  final match = RegExp(r'^(\d+)').firstMatch(chapter);
  final number = match?.group(1) ?? '1';
  return number.padLeft(2, '0');
}

String _legalChapterTitle(String chapter) {
  return chapter.replaceFirst(RegExp(r'^\d+\.\s*'), '').trim();
}

Future<void> _loadLegalChapter(String documentTitle, String chapter) async {
  print('LOAD : $documentTitle / $chapter');
  final documentId = _legalDocumentId(documentTitle);
  final chapterId = _legalChapterId(chapter);

  _selectedLegalDocument = documentTitle;
  _selectedLegalChapter = chapter;
  _legalTitleController.text = _legalChapterTitle(chapter);
  _legalContentController.clear();

  setState(() {});

  final doc = await FirebaseFirestore.instance
      .collection('legalDocuments')
      .doc(documentId)
      .collection('chapters')
      .doc(chapterId)
      .get();

  final data = doc.data();
  print(data);

  if (data != null) {
    _legalTitleController.text =
        (data['title'] ?? _legalChapterTitle(chapter)).toString();

    _legalContentController.text =
        (data['content'] ?? '').toString();

    setState(() {});
  }
}

Future<void> _saveLegalChapter() async {
  if (_selectedLegalDocument == null || _selectedLegalChapter == null) {
    ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(
    content: Text('Aucun chapitre sélectionné.'),
  ),
);
    return;
  }

  final documentId = _legalDocumentId(_selectedLegalDocument!);
  final chapterId = _legalChapterId(_selectedLegalChapter!);
  final order = int.tryParse(chapterId) ?? 1;

  final title = _legalTitleController.text.trim().isEmpty
      ? _legalChapterTitle(_selectedLegalChapter!)
      : _legalTitleController.text.trim();

  final content = _legalContentController.text.trim();

  setState(() {
    _isSavingLegalChapter = true;
    
  });

  try {
    await FirebaseFirestore.instance
        .collection('legalDocuments')
        .doc(documentId)
        .collection('chapters')
        .doc(chapterId)
        .set({
      'order': order,
      'title': title,
      'content': content,
      'isActive': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    setState(() {
      
    });
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Erreur Firebase : $e'),
  ),
);
  } finally {
    if (mounted) {
      setState(() {
        _isSavingLegalChapter = false;
      });
    }
  }
}

void _markLegalVersionModified() {
  if (!_legalVersionButtonRed && !_legalVersionSaved) return;

  setState(() {
    _legalVersionSaved = false;
    _legalVersionButtonRed = false;
  });
}

Future<void> _saveLegalVersionAndTurnButtonRed() async {
  setState(() {
    _legalVersionButtonRed = true;
  });

  await _saveLegalVersion();
}

Future<void> _saveLegalVersion() async {
  if (!_canPublishVersion) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sélectionnez au moins un document, un chapitre modifié et renseignez le résumé des modifications.',
        ),
      ),
    );
    return;
  }

  final now = DateTime.now();

  final version = _legalVersionController.text.trim().isEmpty
      ? '1.0'
      : _legalVersionController.text.trim();

  final versionId = version.replaceAll('.', '_');

  final formattedDate =
      '${now.day.toString().padLeft(2, '0')}/'
      '${now.month.toString().padLeft(2, '0')}/'
      '${now.year}';

  final publicationDate = _legalPublicationDateController.text.trim().isEmpty
      ? formattedDate
      : _legalPublicationDateController.text.trim();

  final summary = _legalChangeLogController.text.trim();

  try {
    final firestore = FirebaseFirestore.instance;

    Future<Map<String, dynamic>> loadDocumentSnapshot({
      required String label,
      required String documentId,
    }) async {
      final doc =
          await firestore.collection('legalDocuments').doc(documentId).get();

      final chaptersSnapshot = await firestore
          .collection('legalDocuments')
          .doc(documentId)
          .collection('chapters')
          .orderBy(FieldPath.documentId)
          .get();

      final selectedChapters = _modifiedChapters[label] ?? <String>{};

      return {
        'label': label,
        'documentId': documentId,
        'modified': _modifiedDocuments.contains(label),
        'modifiedChapters': selectedChapters.toList(),
        'document': doc.data() ?? {},
        'chapters': chaptersSnapshot.docs.map((chapter) {
          return {
            'id': chapter.id,
            ...chapter.data(),
          };
        }).toList(),
      };
    }

    final cguSnapshot = await loadDocumentSnapshot(
      label: 'CGU',
      documentId: 'cgu',
    );

    final privacySnapshot = await loadDocumentSnapshot(
      label: 'Politique de confidentialité',
      documentId: 'privacyPolicy',
    );

    final rgpdSnapshot = await loadDocumentSnapshot(
      label: 'RGPD',
      documentId: 'rgpdNotice',
    );

    final chaptersModified = _modifiedChapters.map(
      (key, value) => MapEntry(key, value.toList()),
    );

    final documentsModified = _modifiedDocuments.toList();

    final versionPayload = {
      'version': version,
      'versionId': versionId,
      'publicationDate': publicationDate,
      'publishedAt': FieldValue.serverTimestamp(),
      'status': _selectedLegalStatus,
      'summary': summary,
      'documentsModified': documentsModified,
      'chaptersModified': chaptersModified,
      'documents': {
        'cgu': cguSnapshot,
        'privacyPolicy': privacySnapshot,
        'rgpdNotice': rgpdSnapshot,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtText': formattedDate,
    };

    await firestore.collection('legalDocuments').doc('metadata').set({
      'version': version,
      'publicationDate': publicationDate,
      'publishedAt': FieldValue.serverTimestamp(),
      'status': _selectedLegalStatus,
      'summary': summary,
      'documentsModified': documentsModified,
      'chaptersModified': chaptersModified,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtText': formattedDate,
    }, SetOptions(merge: true));

    await firestore
        .collection('legalVersions')
        .doc(versionId)
        .set(versionPayload, SetOptions(merge: true));

    if (!mounted) return;

setState(() {
  _legalLastUpdatedText = formattedDate;
  _legalVersionSaved = true;
  _legalVersionButtonRed = true;

  _modifiedDocuments.clear();
  _modifiedChapters['CGU'] = <String>{};
  _modifiedChapters['Politique de confidentialité'] = <String>{};
  _modifiedChapters['RGPD'] = <String>{};

  _legalChangeLogController.clear();
});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Version SPHOT $version publiée et archivée.'),
      ),
    );
  } catch (error) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erreur publication version SPHOT : $error'),
      ),
    );
  }
}

void _openLegalStatusMenu() {
  _dropdownOverlay?.remove();
  _dropdownOverlay = null;

  final renderBox =
      _legalStatusKey.currentContext!.findRenderObject() as RenderBox;

  final position = renderBox.localToGlobal(Offset.zero);
  final size = renderBox.size;

  final statuses = ['Brouillon', 'Publié', 'Archivé'];

  _dropdownOverlay = OverlayEntry(
    builder: (context) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                _dropdownOverlay?.remove();
                _dropdownOverlay = null;
              },
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
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.94),
                  border: const Border(
                    left: BorderSide(color: adminColor, width: 1.4),
                    right: BorderSide(color: adminColor, width: 1.4),
                    bottom: BorderSide(color: adminColor, width: 1.4),
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: statuses.map((status) {
                    final selected = _selectedLegalStatus == status;

                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedLegalStatus = status;
                        });

                        _dropdownOverlay?.remove();
                        _dropdownOverlay = null;
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: selected ? redColor : adminColor,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: selected ? redColor : adminColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
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

@override
void initState() {
  super.initState();
  _speech = stt.SpeechToText();
  _legalVersionController.addListener(_markLegalVersionModified);
  _legalPublicationDateController.addListener(_markLegalVersionModified);
  _legalChangeLogController.addListener(_markLegalVersionModified);
  _loadAllLegalChaptersFromFirebase();
}

@override
void dispose() {
  _speech.stop();
  _dropdownOverlay?.remove();
  _searchController.dispose();
  _legalTitleController.dispose();
  _legalContentController.dispose();
  _legalVersionController.dispose();
  _legalPublicationDateController.dispose();
  _legalVersionController.removeListener(_markLegalVersionModified);
  _legalPublicationDateController.removeListener(_markLegalVersionModified);
  super.dispose();
}

void _updateVisibleCount(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> spots,
) {
  final bounds = _mapController.camera.visibleBounds;

  int count = 0;

  for (final doc in spots) {
    final data = doc.data();

    final lat = _toDouble(data['sphotLat']);
    final lng = _toDouble(data['sphotLng']);

    if (lat != 0 && lng != 0 && bounds.contains(LatLng(lat, lng))) {
      count++;
    }
  }

  if (count != _visibleOnMapSpotCount) {
    setState(() {
      _visibleOnMapSpotCount = count;
    });
  }
}

Future<void> _updateVisibleSauveteurCount(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> spots,
) async {
  final requestId = ++_sauveteurCountRequestId;
  final bounds = _mapController.camera.visibleBounds;

  int count = 0;

  for (final doc in spots) {
    final data = doc.data();

    final lat = _toDouble(data['sphotLat']);
    final lng = _toDouble(data['sphotLng']);

    if (lat == 0 || lng == 0 || !bounds.contains(LatLng(lat, lng))) {
      continue;
    }

    final snap = await doc.reference
        .collection('sauveteursAffectes')
        .get();

    count += snap.docs.length;
  }

  if (!mounted || requestId != _sauveteurCountRequestId) return;

  setState(() {
    _visibleOnMapSauveteurCount = count;
  });
}


Widget _buildMapSearchBar() {
  return Positioned(
    top: 76,
    left: 12,
    right: 12,
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
  onChanged: (value) {
  setState(() {
    _searchText = value;
    _selectedSpot = null;
    _selectedAdmin = null;
    _selectedAdvertiser = null;
  });
},
  textInputAction: TextInputAction.search,

onSubmitted: (value) {
  FocusScope.of(context).unfocus();
  _centerOnFirstCurrentResult();
},
          decoration: InputDecoration(
  hintText: 'Recherche',
  border: InputBorder.none,
  contentPadding: const EdgeInsets.symmetric(vertical: 10),

  prefixIcon: const Icon(
    Icons.search,
    color: Colors.black87,
  ),

  suffixIcon: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    if (_searchText.isNotEmpty)
      IconButton(
        icon: const Icon(
          Icons.close_rounded,
          color: Colors.black54,
          size: 20,
        ),
        onPressed: () {
          _searchController.clear();
          setState(() {
  _searchText = '';
  _selectedSpot = null;
  _selectedAdmin = null;
  _selectedAdvertiser = null;
});
        },
      ),
    IconButton(
      onPressed: _startVoiceSearch,
      icon: const Icon(
        Icons.keyboard_voice_rounded,
        color: Color(0xFFDC2626),
        size: 24,
      ),
    ),
  ],
),
),
        ),
      ),
    ),
  );
}

Widget _buildRecenterButton() {
  return Positioned(
    right: 12,
    bottom: 20,
    child: FloatingActionButton(
      heroTag: 'superAdminRecenter',
      mini: true,
      backgroundColor: Colors.white,
      foregroundColor: adminColor,
      onPressed: () {
        _mapController.move(
          const LatLng(20, 0),
          2.2,
        );
      },
      child: const Icon(Icons.my_location),
    ),
  );
}

Widget _buildNorthButton() {
  return Positioned(
    right: 12,
    bottom: 72,
    child: FloatingActionButton(
      heroTag: 'superAdminNorth',
      mini: true,
      backgroundColor: Colors.white,
      foregroundColor: adminColor,
      onPressed: () {
        _mapController.rotate(0);
      },
      child: const Icon(Icons.navigation),
    ),
  );
}

Widget _buildMapStyleButton() {
  return Positioned(
    right: 12,
    bottom: 124,
    child: FloatingActionButton(
      heroTag: 'superAdminMapStyle',
      mini: true,
      backgroundColor: Colors.white,
      foregroundColor: adminColor,
      onPressed: () {
        setState(() {
          _selectedTileStyle =
              (_selectedTileStyle + 1) % _tileStyles.length;
        });
      },
      child: Icon(
  _selectedTileStyle == 0
      ? Icons.map_outlined
      : _selectedTileStyle == 1
          ? Icons.satellite_alt
          : Icons.terrain,
),
    ),
  );
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

  final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

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

bool _matchesSearch(Map<String, dynamic> data) {
  final query = _normalizeSearch(_searchText);
  if (query.isEmpty) return true;

  final fields = [
    data['nomSphot'],
    data['nomSecours'],
    data['typeSphot'],
    data['natureSphot'],
    data['labelSphot'],
    data['ville'],
    data['departement'],
  ].map((value) => _normalizeSearch((value ?? '').toString())).toList();

  for (final field in fields) {
    if (field.isEmpty) continue;

    if (field.contains(query)) {
      return true;
    }

    final words = field.split(RegExp(r'\s+'));

    for (final word in words) {
      if (_levenshtein(query, word) <= 2) {
        return true;
      }
    }
  }

  return false;
}

void _startVoiceSearch() async {
  if (_isListening) {
    await _speech.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
    return;
  }

  final available = await _speech.initialize(
    onStatus: (status) {
      debugPrint('SPEECH STATUS: $status');

      if (status == 'done' || status == 'notListening') {
        if (mounted) {
          setState(() {
            _isListening = false;
          });
        }
      }
    },
    onError: (error) {
      debugPrint('SPEECH ERROR: $error');

      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    },
  );

  if (!available) {
    debugPrint('SPEECH NON DISPONIBLE');
    return;
  }

  setState(() {
    _isListening = true;
  });

  await _speech.listen(
    localeId: 'fr_FR',
    listenFor: const Duration(seconds: 8),
    pauseFor: const Duration(seconds: 2),
    partialResults: true,
    listenMode: stt.ListenMode.dictation,
    onResult: (result) {
      final text = result.recognizedWords.trim();

      debugPrint('SPEECH TEXT: $text');

      if (text.isEmpty) return;

      final cleanText = text.trim();

_searchController
  ..clear()
  ..text = cleanText
  ..selection = TextSelection.fromPosition(
    TextPosition(offset: cleanText.length),
  );

setState(() {
  _searchText = cleanText;
  _selectedSpot = null;
  _selectedAdmin = null;
  _selectedAdvertiser = null;
});

      if (text.length >= 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _centerOnFirstCurrentResult();
        });
      }

      if (result.finalResult) {
        _speech.stop();

        if (mounted) {
          setState(() {
            _isListening = false;
          });
        }
      }
    },
  );
}

bool _matchesAdminSearch(Map<String, dynamic> data) {
  final query = _normalizeSearch(_searchText);
  if (query.isEmpty) return true;

  final territoire = Map<String, dynamic>.from(data['territoire'] ?? {});
  final structure = Map<String, dynamic>.from(data['structure'] ?? {});
  final profile = Map<String, dynamic>.from(data['profile'] ?? {});

  final fields = [
    data['nomStructure'],
    data['organisation'],
    data['email'],
    data['siret'],
    data['nomResponsable'],
    data['prenom'],
    structure['nom'],
    structure['siret'],
    profile['email'],
    profile['nomAffiche'],
    territoire['ville'],
    territoire['departement'],
    territoire['region'],
  ].map((value) => _normalizeSearch((value ?? '').toString())).toList();

  for (final field in fields) {
    if (field.isEmpty) continue;

    if (field.contains(query)) {
      return true;
    }

    final words = field.split(RegExp(r'\s+'));

    for (final word in words) {
      if (_levenshtein(query, word) <= 2) {
        return true;
      }
    }
  }

  return false;
}

int _searchScore(List<dynamic> values) {
  final query = _normalizeSearch(_searchText);
  if (query.isEmpty) return 0;

  int bestScore = 0;

  for (final value in values) {
    final field = _normalizeSearch((value ?? '').toString());
    if (field.isEmpty) continue;

    if (field == query) bestScore = bestScore < 1000 ? 1000 : bestScore;
    if (field.startsWith(query)) bestScore = bestScore < 800 ? 800 : bestScore;
    if (field.contains(query)) bestScore = bestScore < 600 ? 600 : bestScore;

    final words = field.split(RegExp(r'\s+'));

    for (final word in words) {
      if (word == query) bestScore = bestScore < 900 ? 900 : bestScore;
      if (word.startsWith(query)) bestScore = bestScore < 700 ? 700 : bestScore;

      final distance = _levenshtein(query, word);

      if (distance <= 1) bestScore = bestScore < 650 ? 650 : bestScore;
      if (distance == 2) bestScore = bestScore < 450 ? 450 : bestScore;
    }
  }

  return bestScore;
}

void _centerOnFirstCurrentResult() {
  final results = <Map<String, dynamic>>[];

  for (final doc in _latestSpotDocs) {
    final data = doc.data();
    final lat = _toDouble(data['sphotLat']);
    final lng = _toDouble(data['sphotLng']);

    final score = _searchScore([
      data['nomSphot'],
      data['nomSecours'],
      data['typeSphot'],
      data['natureSphot'],
      data['labelSphot'],
      data['ville'],
      data['departement'],
    ]);

    if (lat != 0 && lng != 0 && score > 0) {
      results.add({
        'type': 'spot',
        'score': score,
        'data': data,
        'lat': lat,
        'lng': lng,
        'zoom': 16.0,
      });
    }
  }

  for (final doc in _latestAdminDocs) {
    final data = doc.data();
    final territoire = Map<String, dynamic>.from(data['territoire'] ?? {});
    final structure = Map<String, dynamic>.from(data['structure'] ?? {});
    final profile = Map<String, dynamic>.from(data['profile'] ?? {});

    final lat = _toDouble(territoire['villeLat']);
    final lng = _toDouble(territoire['villeLng']);

    final score = _searchScore([
      data['nomStructure'],
      data['organisation'],
      data['email'],
      data['siret'],
      data['nomResponsable'],
      structure['nom'],
      structure['siret'],
      profile['email'],
      profile['nomAffiche'],
      territoire['ville'],
      territoire['departement'],
      territoire['region'],
    ]);

    if (lat != 0 && lng != 0 && score > 0) {
      results.add({
        'type': 'admin',
        'score': score,
        'data': data,
        'lat': lat,
        'lng': lng,
        'zoom': 18.0,
      });
    }
  }

  for (final doc in _latestAdDocs) {
    final data = {
      ...doc.data(),
      'id': doc.id,
    };

    final lat = _toDouble(data['centerLat']);
    final lng = _toDouble(data['centerLng']);

    final score = _searchScore([
      data['advertiserName'],
      data['contactName'],
      data['email'],
      data['phone'],
      data['siret'],
      data['city'],
      data['department'],
      data['region'],
      data['status'],
      data['broadcastType'],
      data['visibilityLabel'],
      data['campaignTitle'],
      data['companyName'],
      data['businessName'],
      data['organisation'],
    ]);

    if (lat != 0 && lng != 0 && score > 0) {
      results.add({
        'type': 'advertiser',
        'score': score,
        'data': data,
        'lat': lat,
        'lng': lng,
        'zoom': 16.0,
      });
    }
  }

  if (results.isEmpty) return;

  results.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

  final best = results.first;
  final type = best['type'];
  final data = Map<String, dynamic>.from(best['data']);

  setState(() {
    _selectedSpot = type == 'spot' ? data : null;
    _selectedAdmin = type == 'admin' ? data : null;
    _selectedAdvertiser = type == 'advertiser' ? data : null;
  });

  _mapController.move(
    LatLng(best['lat'] as double, best['lng'] as double),
    best['zoom'] as double,
  );
}

Marker _buildAdminMarker(Map<String, dynamic> data) {
  final territoire = Map<String, dynamic>.from(data['territoire'] ?? {});
  final lat = _toDouble(territoire['villeLat']);
  final lng = _toDouble(territoire['villeLng']);

  final organisation = _cleanText(
    data['nomStructure'] ??
        data['organisation'] ??
        territoire['ville'] ??
        'Admin',
  );

  final logoUrl = _cleanText(territoire['logoVille']);

  return Marker(
    point: LatLng(lat, lng),
    width: 46,
    height: 46,
    child: GestureDetector(
  onTap: () {
    setState(() {
      _selectedSpot = null;
      _selectedAdmin = data;
      _selectedAdvertiser = null;
    });

    _mapController.move(
      LatLng(lat, lng),
      18,
    );
  },
  child: Tooltip(
    message: organisation,
    child: logoUrl.isNotEmpty
        ? ClipOval(
            child: Image.network(
              logoUrl,
              width: 42,
              height: 42,
              fit: BoxFit.cover,
            ),
          )
        : const Icon(
            Icons.account_balance,
            color: adminColor,
            size: 34,
          ),
  ),
),
  );
}

Color _advertiserMarkerColor(Map<String, dynamic> data) {
  final status = _cleanText(data['status']).toLowerCase();

  if (status == 'active') return const Color(0xFF16A34A);
  if (status == 'disabled') return const Color(0xFF6B7280);
  if (status == 'deleted') return const Color(0xFF111827);
  if (status == 'pending') return const Color(0xFFF59E0B);

  return redColor;
}

Marker _buildAdvertiserMarker(Map<String, dynamic> data) {
  final lat = _toDouble(data['centerLat']);
  final lng = _toDouble(data['centerLng']);

  final name = _cleanText(
    data['advertiserName'] ??
        data['companyName'] ??
        data['businessName'] ??
        'Annonceur',
  );

  return Marker(
    point: LatLng(lat, lng),
    width: 34,
    height: 34,
    child: GestureDetector(
      onTap: () {
        setState(() {
          _selectedSpot = null;
          _selectedAdmin = null;
          _selectedAdvertiser = data;
        });

        _mapController.move(LatLng(lat, lng), 18);
      },
      child: Tooltip(
        message: name,
        child: Icon(
          Icons.location_on,
          color: _advertiserMarkerColor(data),
          size: 34,
        ),
      ),
    ),
  );
}

void _updateVisibleAdminCount(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> admins,
) {
  final bounds = _mapController.camera.visibleBounds;
  int count = 0;

  for (final doc in admins) {
    final data = doc.data();
    final territoire = Map<String, dynamic>.from(data['territoire'] ?? {});

    final lat = _toDouble(territoire['villeLat']);
    final lng = _toDouble(territoire['villeLng']);

    if (lat != 0 && lng != 0 && bounds.contains(LatLng(lat, lng))) {
      count++;
    }
  }

  if (count != _visibleOnMapAdminCount) {
    setState(() {
      _visibleOnMapAdminCount = count;
    });
  }
}

void _updateVisibleAdvertiserCount(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> advertisers,
) {
  final bounds = _mapController.camera.visibleBounds;
  int count = 0;

  for (final doc in advertisers) {
    final data = doc.data();

    final lat = _toDouble(data['centerLat']);
    final lng = _toDouble(data['centerLng']);

    if (lat != 0 && lng != 0 && bounds.contains(LatLng(lat, lng))) {
      count++;
    }
  }

  if (count != _visibleAdvertiserCount) {
    setState(() {
      _visibleAdvertiserCount = count;
    });
  }
}

@override
Widget build(BuildContext context) {
  return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
  stream: _spotsStream,
  builder: (context, spotsSnapshot) {
      if (spotsSnapshot.hasError) {
        return Center(
          child: Text('Erreur Dashboard Map : ${spotsSnapshot.error}'),
        );
      }

      if (!spotsSnapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _adminRequestsStream,
        builder: (context, adminsSnapshot) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _subscriptionsStream,
            builder: (context, subscriptionsSnapshot) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _adRequestsStream,
                builder: (context, adsSnapshot) {
                  final docs = spotsSnapshot.data ?? [];
                  _latestSpotDocs = docs;

                  final subscriptionsDocs =
                      subscriptionsSnapshot.data?.docs ?? [];

                  _subscriptionsByUid = {
                    for (final doc in subscriptionsDocs) doc.id: doc.data(),
                  };

                  final validSpots = docs.where((doc) {
  final data = doc.data();
  final lat = _toDouble(data['sphotLat']);
  final lng = _toDouble(data['sphotLng']);

  return lat != 0 &&
      lng != 0 &&
      _matchesFilter(data);
}).toList();

                  final adminDocs = adminsSnapshot.data?.docs ?? [];
                  _latestAdminDocs = adminDocs;

                  final validAdmins = adminDocs.where((doc) {
                    final data = doc.data();
                    final territoire =
                        Map<String, dynamic>.from(data['territoire'] ?? {});

                    final lat = _toDouble(territoire['villeLat']);
                    final lng = _toDouble(territoire['villeLng']);

                    return lat != 0 &&
      lng != 0 &&
      _matchesAdminFilter(data);
}).toList();

                  final adDocs = adsSnapshot.data?.docs ?? [];

                  _latestAdDocs = adDocs;

                  final validAdvertisers = adDocs.where((doc) {
                    final data = doc.data();
                    final lat = _toDouble(data['centerLat']);
                    final lng = _toDouble(data['centerLng']);

                    return lat != 0 &&
                        lng != 0 &&
                        _matchesAdvertiserFilter(data) &&
                        _matchesAdvertiserSearch(data);
                  }).toList();

                  WidgetsBinding.instance.addPostFrameCallback((_) {
  _updateVisibleCount(validSpots);
  _updateVisibleAdminCount(validAdmins);
  _updateVisibleAdvertiserCount(validAdvertisers);
  _updateVisibleSauveteurCount(validSpots);
});

                  final markers = <Marker>[
                    ...validSpots.map((doc) => _buildSpotMarker(doc.data())),
                    ...validAdmins.map((doc) => _buildAdminMarker(doc.data())),
                    ...validAdvertisers.map((doc) {
                      return _buildAdvertiserMarker({
                        ...doc.data(),
                        'id': doc.id,
                      });
                    }),
                  ];

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildRightPanel(
                        visibleSpots: validSpots.length,
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: const LatLng(20, 0),
                                initialZoom: 2.2,
                                minZoom: 2,
                                maxZoom: 18,
                                onTap: (_, __) {
  setState(() {
    _selectedSpot = null;
    _selectedAdmin = null;
    _selectedAdvertiser = null;

    _showLegalDocumentsPanel = false;
    _selectedLegalDocument = null;
    _selectedLegalChapter = null;
  });
},
                                onPositionChanged: (_, __) {
                                  _updateVisibleCount(validSpots);
                                  _updateVisibleAdminCount(validAdmins);
                                  _updateVisibleAdvertiserCount(validAdvertisers);
                                  _updateVisibleSauveteurCount(validSpots);
                                },
                              ),
                              children: [
                                TileLayer(
                                  key: ValueKey(
                                    'super_admin_tile_$_selectedTileStyle',
                                  ),
                                  urlTemplate:
                                      _tileStyles[_selectedTileStyle].url,
                                  subdomains:
                                      _tileStyles[_selectedTileStyle].subdomains,
                                  maxZoom: _tileStyles[_selectedTileStyle]
                                      .maxZoom
                                      .toDouble(),
                                  maxNativeZoom:
                                      _tileStyles[_selectedTileStyle].maxZoom,
                                  userAgentPackageName: 'com.sylvainra.sphot',
                                ),
                                MarkerClusterLayerWidget(
                                  options: MarkerClusterLayerOptions(
                                    markers: markers,
                                    size: const Size(54, 54),
                                    maxClusterRadius: 45,
                                    disableClusteringAtZoom: 15,
                                    builder: (context, clusterMarkers) {
                                      final clusterColor =
                                          _clusterBorderColor(clusterMarkers);
                                      final iconPath =
                                          _clusterIconPath(clusterColor);
                                      final count =
                                          clusterMarkers.length.toString();

                                      return SizedBox(
                                        width: 54,
                                        height: 54,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Image.asset(
                                              iconPath,
                                              width: 54,
                                              height: 54,
                                              fit: BoxFit.contain,
                                              filterQuality: FilterQuality.high,
                                            ),
                                            Text(
  count,
  textAlign: TextAlign.center,
  style: TextStyle(
    fontSize: count.length >= 3 ? 13 : 16,
    fontWeight: FontWeight.w900,
    color: Colors.black87,
    shadows: const [
      Shadow(
        color: Colors.white70,
        offset: Offset(0.5, 0.5),
        blurRadius: 1,
      ),
    ],
  ),
),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            Positioned(
                              top: 8,
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
                            _buildMapSearchBar(),
_buildRecenterButton(),
_buildNorthButton(),
_buildMapStyleButton(),

Positioned(
  left: 0,
  right: 0,
  bottom: 22,
  child: Center(
    child: IconButton(
      icon: const Icon(
        Icons.arrow_back_ios_new_rounded,
        color: adminColor,
        size: 34,
      ),
      onPressed: () {
        Navigator.of(context).pop();
      },
    ),
  ),
),
                          ],
                        ),
                      ),

                      if (_showLegalDocumentsPanel)
  _buildLegalDocumentsPanel()
else if (_selectedSpot != null)
  _buildSpotDetailPanel()
else if (_selectedAdvertiser != null)
  _buildAdvertiserDetailPanel()
else if (_selectedAdmin != null)
  _buildAdminDetailPanel(),
                    ],
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

}
class DashboardSpotMarker extends StatelessWidget {
  final Map<String, dynamic> data;
  final String name;
  final String iconPath;
  final Color typeColor;

  const DashboardSpotMarker({
    super.key,
    required this.data,
    required this.name,
    required this.iconPath,
    required this.typeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      iconPath,
      width: 46,
      height: 46,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) {
        return Icon(
          Icons.place,
          color: typeColor,
          size: 34,
        );
      },
    );
  }
}

