import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../../map/map_page.dart';
import '../../../widgets/adaptive_asset_image.dart';
import '../../shared/web_colors.dart';
import '../models/diffusion_preview_data.dart';
import '../widgets/advertising_spot_section.dart';
import '../widgets/diffusion_central_preview.dart';
import '../widgets/diffusion_section.dart';
import '../widgets/establishment_section.dart';
import '../widgets/identity_professional_section.dart';

class AdvertiserDashboardPage extends StatefulWidget {
  const AdvertiserDashboardPage({
    super.key,
    required this.user,
    required this.onSignOut,
    this.developmentBypass = false,
  });

  final User? user;
  final Future<void> Function() onSignOut;
  final bool developmentBypass;

  @override
  State<AdvertiserDashboardPage> createState() =>
      _AdvertiserDashboardPageState();
}

class _AdvertiserDashboardPageState extends State<AdvertiserDashboardPage> {
  static const _sections = <_AdvertiserSection>[
    _AdvertiserSection(
      'IDENTITÉ PROFESSIONNELLE',
      Icons.verified_user_outlined,
      'Identité certifiée par ProConnect et informations de contact.',
    ),
    _AdvertiserSection(
      'ÉTABLISSEMENT',
      Icons.storefront_outlined,
      'Établissement, activité et coordonnées publiques.',
    ),
    _AdvertiserSection(
      'SPHOT PUBLICITAIRE',
      Icons.location_on_outlined,
      'Positionnez l’établissement qui portera votre publicité.',
    ),
    _AdvertiserSection(
      'DIFFUSION',
      Icons.campaign_outlined,
      'Choisissez la CARTE SPHOT, la FICHE SPHOT PREMIUM '
          'ou le PACK VISIBILITÉ TOTALE.',
    ),
    _AdvertiserSection(
      'PLANIFICATION',
      Icons.calendar_month_outlined,
      'Rayonnement, dates et réservation exclusive de l’emplacement.',
    ),
    _AdvertiserSection(
      'DEVIS & COMMANDE',
      Icons.assignment_turned_in_outlined,
      'Tarification, devis, bon de commande et validation.',
    ),
    _AdvertiserSection(
      'DOCUMENTS & FACTURES',
      Icons.description_outlined,
      'Documents contractuels et facturation électronique.',
    ),
    _AdvertiserSection(
      'STATISTIQUES',
      Icons.query_stats_outlined,
      'Affichages, clics et fréquentation de la campagne.',
    ),
  ];

  int _selectedIndex = 0;
  final MapController _mapController = MapController();
  LatLng? _advertisingPoint;
  DiffusionPreviewData _diffusionPreview = const DiffusionPreviewData();

  void _setAdvertisingPoint(LatLng point, {required bool centerMap}) {
    setState(() => _advertisingPoint = point);
    if (!centerMap) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(point, 15);
    });
  }

  void _setDiffusionPreview(DiffusionPreviewData preview) {
    if (!mounted) return;
    setState(() => _diffusionPreview = preview);
  }

  void _returnToPublicMap() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MapPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1250;
          final sidebarWidth = compact ? 250.0 : 330.0;
          final panelWidth = compact ? 370.0 : 470.0;

          return Row(
            children: [
              SizedBox(width: sidebarWidth, child: _buildSidebar()),
              Expanded(child: _buildMap()),
              SizedBox(width: panelWidth, child: _buildDetailPanel()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebar() {
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          child: Column(
            children: [
              const Text(
                'ESPACE ANNONCEUR',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: WebColors.red,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(_sections.length, (index) {
                    return _SidebarButton(
                      number: index + 1,
                      label: _sections[index].label,
                      selected: index == _selectedIndex,
                      onTap: () => setState(() => _selectedIndex = index),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (_selectedIndex == 3 && _diffusionPreview.hasSelection) {
      return DiffusionCentralPreview(
        data: _diffusionPreview,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(46.6, 2.4),
            initialZoom: 5.4,
            minZoom: 4,
            maxZoom: 18,
            onTap: _selectedIndex == 2
                ? (_, point) =>
                    _setAdvertisingPoint(point, centerMap: false)
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sphot.app',
            ),
            if (_advertisingPoint != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _advertisingPoint!,
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: const Offset(0, -28),
                      child: AdaptiveAssetImage(
                        'data/icons/fire_red_icon.svg',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (_selectedIndex == 2)
          Positioned(
            top: 88,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: WebColors.blue, width: 1.4),
                  ),
                  child: const Text(
                    'CLIQUEZ SUR LA CARTE POUR AJUSTER LE SPHOT PUBLICITAIRE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: WebColors.blue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
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
        Positioned(
          left: 0,
          right: 0,
          bottom: 22,
          child: Center(
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: WebColors.blue, width: 2),
              ),
              child: IconButton(
                onPressed: _returnToPublicMap,
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: WebColors.blue,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailPanel() {
    final section = _sections[_selectedIndex];

    return ColoredBox(
      color: const Color(0xFFF5F7FA),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 100,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFD5DCE8))),
              ),
              child: Row(
                children: [
                  SvgPicture.asset(
                    'data/icons/fire_red_icon.svg',
                    width: 38,
                    height: 54,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      section.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WebColors.blue,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      section.description,
                      style: const TextStyle(
                        color: WebColors.blue,
                        fontSize: 16,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ..._buildSectionContent(_selectedIndex),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSectionContent(int index) {
    switch (index) {
      case 0:
        return [
          IdentityProfessionalSection(
            user: widget.user,
          ),
        ];
      case 1:
        return [
          EstablishmentSection(user: widget.user),
        ];
      case 2:
        return [
          AdvertisingSpotSection(
            user: widget.user,
            position: _advertisingPoint,
            onPositionChanged: _setAdvertisingPoint,
          ),
        ];
      case 3:
        return [
          DiffusionSection(
            user: widget.user,
            advertisingPosition: _advertisingPoint,
            onPreviewChanged: _setDiffusionPreview,
          ),
        ];
      case 4:
        return const [
          _StatusCard(
            icon: Icons.event_available_outlined,
            title: 'RÉSERVATION EXCLUSIVE',
            description: 'Une seule campagne peut occuper un emplacement donné pendant une même période.',
            status: 'RÈGLE COMMERCIALE ACTIVE',
            statusColor: Color(0xFF15803D),
          ),
          _StatusCard(
            icon: Icons.radar_outlined,
            title: 'RAYONNEMENT',
            description: 'La disponibilité sera calculée selon l’épicentre, le rayon, les SPHOTS couverts et les dates.',
            status: 'À CONFIGURER',
          ),
        ];
      case 6:
        return const [
          _StatusCard(
            icon: Icons.receipt_long_outlined,
            title: 'FACTURATION ÉLECTRONIQUE',
            description: 'Numérotation, intégrité et transmission seront préparées pour une plateforme agréée.',
            status: 'À RACCORDER',
          ),
          _StatusCard(
            icon: Icons.inventory_2_outlined,
            title: 'ARCHIVAGE',
            description: 'Les documents finalisés seront conservés sans écrasement et corrigés par avoir ou facture rectificative.',
            status: 'À RACCORDER',
          ),
        ];
      default:
        return [
          _StatusCard(
            icon: _sections[index].icon,
            title: _sections[index].label,
            description: 'Cette rubrique est prête à recevoir les données et règles déjà validées du parcours annonceur.',
            status: 'À COMPLÉTER',
          ),
        ];
    }
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.number,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? WebColors.red : WebColors.blue;

    final icon = AdaptiveAssetImage(
      'data/icons/fire_red_icon.svg',
      width: 44,
      height: 56,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    return SizedBox(
      height: 72,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  icon,
                  Text(
                    '$number',
                    style: TextStyle(
                      color: selected ? WebColors.red : WebColors.blue,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    this.statusColor = const Color(0xFF6B7280),
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: WebColors.blue, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: WebColors.blue,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF4B5F97),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
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
}

class _AdvertiserSection {
  const _AdvertiserSection(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;
}
