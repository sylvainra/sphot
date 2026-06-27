import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

enum DashboardSpotFilter {
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
  all,
  trial,
  active,
  overdue,
  cancelled,
}

enum DashboardAdvertiserFilter {
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

int _visibleAdvertiserCount = 0;

final GlobalKey _advertiserFiltersKey = GlobalKey();

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

  OverlayEntry? _dropdownOverlay;

  final GlobalKey _filtersKey = GlobalKey();
  final GlobalKey _adminFiltersKey = GlobalKey();

  final Set<DashboardSpotFilter> _selectedFilters = {
    DashboardSpotFilter.all,
  };

  DashboardAdminFilter _selectedAdminFilter =
      DashboardAdminFilter.all;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _spotsStream {
    return FirebaseFirestore.instance.collection('spots').snapshots();
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
  if (_selectedFilters.contains(DashboardSpotFilter.all)) {
    return true;
  }

  return _selectedFilters.any((filter) {
    final previous = _selectedFilters;
    switch (filter) {
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ScrollbarTheme(
                      data: ScrollbarThemeData(
                        thumbColor: MaterialStatePropertyAll(adminColor),
                        trackVisibility:
                            const MaterialStatePropertyAll(false),
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
                            final selected =
                                _selectedFilters.contains(filter);

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  if (filter == DashboardSpotFilter.all) {
                                    _selectedFilters
                                      ..clear()
                                      ..add(DashboardSpotFilter.all);
                                  } else {
                                    _selectedFilters
                                        .remove(DashboardSpotFilter.all);

                                    if (selected) {
                                      _selectedFilters.remove(filter);
                                    } else {
                                      _selectedFilters.add(filter);
                                    }

                                    if (_selectedFilters.isEmpty) {
                                      _selectedFilters
                                          .add(DashboardSpotFilter.all);
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
                                          : Icons
                                              .check_box_outline_blank_rounded,
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
                                          color: selected
                                              ? redColor
                                              : adminColor,
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
    width: 50,
    height: 50,
    child: GestureDetector(
      onTap: () {
  setState(() {
    _selectedSpot = data;
    _selectedAdmin = null;
    _selectedAdvertiser = null;
  });

  _mapController.move(
    LatLng(lat, lng),
    18,
  );
},
      child: DashboardSpotMarker(
        data: data,
        name: name,
        iconPath: iconPath,
        typeColor: _spotTypeColor(data),
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
      child: SingleChildScrollView(
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

const SizedBox(height: 28),

            if (_selectedSpot != null) _selectedSpotCard(),
            if (_selectedAdmin != null) _selectedAdminCard(),
          ],
        ),
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

  switch (_selectedAdvertiserFilter) {

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
      showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Image.network(
              bannerUrl,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    },
    child: Container(
    width: double.infinity,
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: adminColor.withOpacity(0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: adminColor.withOpacity(0.25)),
    ),
    child: Row(
      children: [
        const Icon(Icons.image_rounded, color: adminColor, size: 22),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Bannière publicitaire',
            style: TextStyle(
              color: adminColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Icon(
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

Widget _buildAdvertisersList() {
  return const SizedBox.shrink();
}


@override
void initState() {
  super.initState();
  _speech = stt.SpeechToText();
}

@override
void dispose() {
  _speech.stop();
  _dropdownOverlay?.remove();
  _searchController.dispose();
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

    if (bounds.contains(LatLng(lat, lng))) {
      count++;
    }
  }

  if (count != _visibleOnMapSpotCount) {
    setState(() {
      _visibleOnMapSpotCount = count;
    });
  }
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
  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                  final docs = spotsSnapshot.data!.docs;
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
                        _matchesFilter(data) &&
                        _matchesSearch(data);
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
                        _matchesAdminFilter(data) &&
                        _matchesAdminSearch(data);
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
                                  });
                                },
                                onPositionChanged: (_, __) {
                                  _updateVisibleCount(validSpots);
                                  _updateVisibleAdminCount(validAdmins);
                                  _updateVisibleAdvertiserCount(validAdvertisers);
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
                                                fontSize:
                                                    count.length >= 3 ? 13 : 16,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                                shadows: const [
                                                  Shadow(
                                                    color: Colors.black,
                                                    offset: Offset(1, 1),
                                                    blurRadius: 2,
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
                          ],
                        ),
                      ),
                      if (_selectedAdvertiser != null)
                        _buildAdvertiserDetailPanel(),
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
    return Tooltip(
      message: name,
      child: Image.asset(
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
      ),
    );
  }
}
