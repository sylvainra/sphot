import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';

import '../models/flag_state.dart';
import '../services/firestore_service.dart';
import 'flag_marker.dart';

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

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final FirestoreService _firestoreService = FirestoreService();
  SpotFilter _selectedFilter = SpotFilter.all;

  bool _showFlagForZoom(double zoom) => zoom >= 12.5;
  bool _showTextForZoom(double zoom) => zoom >= 13.0;

  double _labelOpacity(double zoom) {
    if (zoom >= 14.5) return 1.0;
    if (zoom >= 13.8) return 0.88;
    if (zoom >= 13.0) return 0.72;
    return 0.0;
  }

  String _getMarkerIconPath(SpotFlagState spot) {
    final type = spot.normalizedType;

    if (spot.isNaturisme) return 'data/icons/fire_icon.png';
    if (type.contains('ACCES PLAGE')) return 'data/icons/fire_kaki_icon.png';

    if (type.contains('LAC') ||
        type.contains('PISCINE NATURELLE') ||
        type.contains('CASCADE')) {
      return 'data/icons/fire_blue_icon.png';
    }

    if (type.contains('FLEUVE') ||
        type.contains('RIVIERE') ||
        type.contains('BARRAGE')) {
      return 'data/icons/fire_green_icon.png';
    }

    if (type.contains('LAGON')) return 'data/icons/fire_cyan_icon.png';

    return 'data/icons/fire_yellow_icon.png';
  }

  Color _typeColor(SpotFlagState spot) {
    final type = spot.normalizedType;

    if (spot.isPosteSecours) return const Color(0xFFFF0000);
    if (spot.isNaturisme) return const Color(0xFFFEC3AC);
    if (type.contains('ACCES PLAGE')) return const Color(0xFF568203);

    if (type.contains('LAC') ||
        type.contains('FLEUVE') ||
        type.contains('CASCADE') ||
        type.contains('BARRAGE')) {
      return const Color(0xFF0A53A8);
    }

    if (type.contains('RIVIERE') || type.contains('PISCINE NATURELLE')) {
      return const Color(0xFF4201FF);
    }

    if (type.contains('LAGON')) return const Color(0xFF00FFFA);

    return Colors.black;
  }

  bool _matchesFilter(SpotFlagState spot) {
    final type = spot.normalizedType;

    switch (_selectedFilter) {
      case SpotFilter.all:
        return true;
      case SpotFilter.secours:
        return spot.isPosteSecours;
      case SpotFilter.accesPlage:
        return type.contains('ACCES PLAGE');
      case SpotFilter.eauBleue:
        return type.contains('LAC') ||
            type.contains('CASCADE') ||
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

  String _filterLabel(SpotFilter filter) {
    switch (filter) {
      case SpotFilter.all:
        return 'Tous les SPHOTS';
      case SpotFilter.secours:
        return 'SPHOT Secours';
      case SpotFilter.accesPlage:
        return 'SPHOT Accès plage';
      case SpotFilter.eauBleue:
        return 'SPHOT Lac / Cascade / Barrage';
      case SpotFilter.eauVerte:
        return 'SPHOT Fleuve / Rivière';
      case SpotFilter.lagon:
        return 'SPHOT Lagon / Piscine naturelle';
      case SpotFilter.naturisme:
        return 'SPHOT Naturisme';
      case SpotFilter.autre:
        return 'SPHOT Autre / Non renseigné';
    }
  }

  Color _filterColor(SpotFilter filter) {
    switch (filter) {
      case SpotFilter.all:
        return Colors.black87;
      case SpotFilter.secours:
        return const Color(0xFFFF0000);
      case SpotFilter.accesPlage:
        return const Color(0xFF568203);
      case SpotFilter.eauBleue:
        return const Color(0xFF0A53A8);
      case SpotFilter.eauVerte:
        return const Color(0xFF4201FF);
      case SpotFilter.lagon:
        return const Color(0xFF00FFFA);
      case SpotFilter.naturisme:
        return const Color(0xFFFEC3AC);
      case SpotFilter.autre:
        return Colors.black87;
    }
  }

  Color _filterOutlineColor(SpotFilter filter) {
    switch (filter) {
      case SpotFilter.lagon:
        return const Color(0xFF00B8B5);
      case SpotFilter.naturisme:
        return const Color(0xFFE97958);
      default:
        return Colors.transparent;
    }
  }

  Widget _drawerAssetIcon(String path) {
    return Image.asset(path, width: 40, height: 40, fit: BoxFit.contain);
  }

  Widget _filterIcon(SpotFilter filter) {
    switch (filter) {
      case SpotFilter.all:
        return const Text('🌍', style: TextStyle(fontSize: 22));
      case SpotFilter.secours:
        return const _DrawerFlagIcon();
      case SpotFilter.accesPlage:
        return _drawerAssetIcon('data/icons/fire_kaki_icon.png');
      case SpotFilter.eauBleue:
        return _drawerAssetIcon('data/icons/fire_blue_icon.png');
      case SpotFilter.eauVerte:
        return _drawerAssetIcon('data/icons/fire_green_icon.png');
      case SpotFilter.lagon:
        return _drawerAssetIcon('data/icons/fire_cyan_icon.png');
      case SpotFilter.naturisme:
        return _drawerAssetIcon('data/icons/fire_icon.png');
      case SpotFilter.autre:
        return _drawerAssetIcon('data/icons/fire_black_icon.png');
    }
  }

  Marker _buildOtherSpotMarker(SpotFlagState spot, bool showText, double zoom) {
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
        labelOpacity: _labelOpacity(zoom),
      ),
    );
  }

  List<Marker> _buildMarkers(List<SpotFlagState> spots, double zoom) {
    final showFlag = _showFlagForZoom(zoom);
    final showText = _showTextForZoom(zoom);

    return spots.where(_matchesFilter).map((spot) {
      if (spot.isPosteSecours) {
        return _buildSecoursMarker(spot, showFlag, showText, zoom);
      }
      return _buildOtherSpotMarker(spot, showText, zoom);
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
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Row(
                  children: [
                    _ColoredHamburgerIcon(size: 26),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SPHOT',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'Menu',
                          style: TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _sectionTitle('SPHOTS'),
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
                            outlineColor: _filterOutlineColor(filter),
                            outlined: filter == SpotFilter.lagon ||
                                filter == SpotFilter.naturisme,
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
                    _sectionTitle('INFORMATIONS'),
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

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: Colors.black54,
          letterSpacing: 0.7,
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

    return colors.length == 1 ? colors.first : Colors.black;
  }

  Widget _buildCluster(BuildContext context, List<Marker> markers) {
    final borderColor = _clusterBorderColor(markers);

    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
        border: Border.all(color: borderColor, width: 2.2),
      ),
      child: Text(
        markers.length.toString(),
        style: _mapLabelStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: borderColor,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: 'Menu',
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: const _ColoredHamburgerIcon(size: 25),
        ),
      ),
      title: const Text(
        'SPHOT',
        style: TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.account_circle_outlined),
          color: Colors.black87,
          tooltip: 'Connexion sauveteurs',
          onPressed: () {},
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawerScrimColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: StreamBuilder<List<SpotFlagState>>(
        stream: _firestoreService.getSpotsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final spots = snapshot.data!;

          return FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(46.4006176, -1.5064563),
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.sphot',
              ),
              Builder(
                builder: (context) {
                  final zoom = MapCamera.of(context).zoom;
                  final markers = _buildMarkers(spots, zoom);
                  return MarkerClusterLayerWidget(
                    options: MarkerClusterLayerOptions(
                      markers: markers,
                      size: const Size(42, 42),
                      maxClusterRadius: 45,
                      builder: _buildCluster,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OutlinedMenuText extends StatelessWidget {
  final String text;
  final Color color;
  final Color outlineColor;
  final bool outlined;
  final bool selected;

  const _OutlinedMenuText({
    required this.text,
    required this.color,
    required this.outlineColor,
    required this.outlined,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final weight = selected ? FontWeight.w900 : FontWeight.w700;

    if (!outlined) {
      return Text(text, style: TextStyle(color: color, fontWeight: weight));
    }

    return Stack(
      children: [
        Text(
          text,
          style: TextStyle(
            fontWeight: weight,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.1
              ..color = outlineColor,
          ),
        ),
        Text(text, style: TextStyle(color: color, fontWeight: weight)),
      ],
    );
  }
}

class _ColoredHamburgerIcon extends StatelessWidget {
  final double size;

  const _ColoredHamburgerIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    final lineHeight = size * 0.12;
    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _line(size, lineHeight, const Color(0xFF00A651)),
          SizedBox(height: size * 0.15),
          _line(size, lineHeight, const Color(0xFFFFFF00)),
          SizedBox(height: size * 0.15),
          _line(size, lineHeight, const Color(0xFFFF0000)),
        ],
      ),
    );
  }

  Widget _line(double width, double height, Color color) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.black.withOpacity(0.25), width: 0.3),
      ),
    );
  }
}

class _DrawerFlagIcon extends StatelessWidget {
  const _DrawerFlagIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 7,
            bottom: 0,
            child: Container(
              width: 3,
              height: 31,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 4,
            child: CustomPaint(
              size: const Size(20, 15),
              painter: _MiniFlagPainter(color: const Color(0xFF22C55E)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniFlagPainter extends CustomPainter {
  final Color color;

  _MiniFlagPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 2)
      ..quadraticBezierTo(size.width * 0.45, -2, size.width, 2)
      ..lineTo(size.width, size.height - 3)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height + 2,
        0,
        size.height - 2,
      )
      ..close();

    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniFlagPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _OtherSpotMarker extends StatefulWidget {
  final SpotFlagState spot;
  final String iconPath;
  final bool showTextAllowed;
  final double zoom;
  final double labelOpacity;
  final Color typeTextColor;

  const _OtherSpotMarker({
    required this.spot,
    required this.iconPath,
    required this.showTextAllowed,
    required this.zoom,
    required this.labelOpacity,
    required this.typeTextColor,
  });

  @override
  State<_OtherSpotMarker> createState() => _OtherSpotMarkerState();
}

class _OtherSpotMarkerState extends State<_OtherSpotMarker> {
  bool isHovering = false;

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
    final showText = isHovering && widget.showTextAllowed;

    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      child: SizedBox(
        width: 56,
        height: 56,
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
                top: 48,
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
                        const SizedBox(height: 1),
                        Text(
                          spot.typeSphot,
                          textAlign: TextAlign.center,
                          style: _mapLabelStyle(
                            fontSize: _labelSize(10),
                            fontWeight: FontWeight.w700,
                            color: widget.typeTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
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
  final double labelOpacity;

  const _HoverMarker({
    required this.spot,
    required this.showTextAllowed,
    required this.zoom,
    required this.labelOpacity,
  });

  @override
  State<_HoverMarker> createState() => _HoverMarkerState();
}

class _HoverMarkerState extends State<_HoverMarker> {
  bool isHovering = false;

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
    final showText = isHovering && widget.showTextAllowed;

    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      child: SizedBox(
        width: 70,
        height: 95,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.translate(
              offset: const Offset(0, -47.5),
              child: FlagMarker(spot: spot),
            ),
            if (showText)
              Positioned(
                top: 52,
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
                        const SizedBox(height: 2),
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: _mapLabelStyle(
                              fontSize: _labelSize(10),
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                            children: [
                              const TextSpan(
                                text: '🚨 POSTE DE SECOURS 🚨',
                                style: TextStyle(
                                  color: Color(0xFFFF0000),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (spot.phone.trim().isNotEmpty)
                                TextSpan(text: ' - 📞 ${spot.phone}'),
                              if (spot.heureDebut.trim().isNotEmpty &&
                                  spot.heureFin.trim().isNotEmpty)
                                TextSpan(
                                  text:
                                      ' - 🕘 ${spot.heureDebut} - ${spot.heureFin}',
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (spot.isMissingFlagColorDuringSurveillance) ...[
                          Text(
                            '⚠️ COULEUR DE LA FLAMME NON RENSEIGNÉE',
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _labelSize(10),
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFFF0000),
                            ),
                          ),
                          Text(
                            '⚠️ BAIGNADE À VOS RISQUES ET PÉRILS',
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _labelSize(10),
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFFF0000),
                            ),
                          ),
                        ] else
                          Text(
                            spot.displayStatut,
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _labelSize(10),
                              fontWeight: FontWeight.w900,
                              color: Color(spot.statutColor),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

TextStyle _mapLabelStyle({
  required double fontSize,
  required FontWeight fontWeight,
  required Color color,
}) {
  return TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: 1.1,
    letterSpacing: -0.1,
    shadows: const [
      Shadow(color: Colors.white, offset: Offset(0, 0), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(1, 0), blurRadius: 1),
      Shadow(color: Colors.white, offset: Offset(-1, 0), blurRadius: 1),
      Shadow(color: Colors.white, offset: Offset(0, 1), blurRadius: 1),
      Shadow(color: Colors.white, offset: Offset(0, -1), blurRadius: 1),
    ],
  );
}