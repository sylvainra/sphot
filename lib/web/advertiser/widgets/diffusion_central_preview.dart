import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/web_colors.dart';
import '../models/diffusion_preview_data.dart';

class DiffusionCentralPreview extends StatelessWidget {
  const DiffusionCentralPreview({super.key, required this.data});

  final DiffusionPreviewData data;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE9EEF5),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isPack = data.type == DiffusionPreviewType.pack;
            final availablePhoneHeight = constraints.maxHeight - 215;
            final heightBasedWidth = (availablePhoneHeight * 0.60)
                .clamp(220.0, 350.0)
                .toDouble();
            final singleWidth = heightBasedWidth;
            final packWidth = ((constraints.maxWidth - 86) / 2)
                .clamp(200.0, heightBasedWidth)
                .toDouble();
            final phoneWidth = isPack ? packWidth : singleWidth;

            return Column(
              children: [
                const SizedBox(height: 18),
                const Text(
                  'APERÇU DE VOTRE PUBLICITÉ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: WebColors.blue,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _previewSubtitle(data.type),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF4B5F97),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (data.type == DiffusionPreviewType.map || isPack)
                            _PreviewColumn(
                              label: 'CARTE SPHOT',
                              detail: 'EMPLACEMENT DÉFINI',
                              phoneWidth: phoneWidth,
                              child: _MapPhonePreview(data: data),
                            ),
                          if (isPack) const SizedBox(width: 26),
                          if (data.type == DiffusionPreviewType.premium ||
                              isPack)
                            _PreviewColumn(
                              label: 'FICHE SPHOT PREMIUM',
                              detail: 'INTÉGRATION INDICATIVE',
                              phoneWidth: phoneWidth,
                              child: _PremiumPhonePreview(data: data),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _previewSubtitle(DiffusionPreviewType? type) {
    return switch (type) {
      DiffusionPreviewType.map =>
        'Visualisez l’emplacement réservé sur la carte principale.',
      DiffusionPreviewType.premium =>
        'Visualisez l’intégration dans la fiche détaillée d’un SPHOT.',
      DiffusionPreviewType.pack =>
        'Comparez vos deux emplacements publicitaires simultanément.',
      null => '',
    };
  }
}

class _PreviewColumn extends StatelessWidget {
  const _PreviewColumn({
    required this.label,
    required this.detail,
    required this.phoneWidth,
    required this.child,
  });

  final String label;
  final String detail;
  final double phoneWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: phoneWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: WebColors.blue,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: WebColors.red,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _openLargePreview(context),
              child: AspectRatio(
                aspectRatio: 0.60,
                child: _PhoneShell(child: child),
              ),
            ),
          ),
          const SizedBox(height: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _openLargePreview(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: WebColors.blue, width: 1.3),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.open_in_full_rounded,
                      color: WebColors.blue,
                      size: 15,
                    ),
                    SizedBox(width: 7),
                    Text(
                      'CLIQUEZ POUR AGRANDIR',
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openLargePreview(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.72),
      builder: (dialogContext) {
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Center(
                    child: SizedBox(
                      width: 360,
                      child: AspectRatio(
                        aspectRatio: 0.60,
                        child: _PhoneShell(child: child),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 24,
                left: 24,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.42),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: IconButton(
                    tooltip: 'Fermer l’aperçu',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PhoneShell extends StatelessWidget {
  const _PhoneShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3A000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(width: 360, height: 600, child: child),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: 70,
                height: 15,
                decoration: const BoxDecoration(
                  color: Color(0xFF111827),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
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

class _MapPhonePreview extends StatelessWidget {
  const _MapPhonePreview({required this.data});

  final DiffusionPreviewData data;

  @override
  Widget build(BuildContext context) {
    final center = LatLng(data.latitude ?? 46.3445, data.longitude ?? -1.4376);

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: FlutterMap(
            key: ValueKey('${center.latitude}:${center.longitude}'),
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15.5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.sphot.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 46,
                    height: 58,
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: const Offset(0, -29),
                      child: SvgPicture.asset(
                        'data/icons/fire_red_icon.svg',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Marker(
                    point: LatLng(
                      center.latitude - 0.0016,
                      center.longitude - 0.0018,
                    ),
                    width: 38,
                    height: 48,
                    alignment: Alignment.center,
                    child: SvgPicture.asset(
                      'data/icons/fire_blue_icon.svg',
                      fit: BoxFit.contain,
                    ),
                  ),
                  Marker(
                    point: LatLng(
                      center.latitude + 0.0014,
                      center.longitude + 0.0020,
                    ),
                    width: 36,
                    height: 45,
                    alignment: Alignment.center,
                    child: SvgPicture.asset(
                      'data/icons/fire_blue_icon.svg',
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: 22,
          left: 18,
          right: 18,
          child: Image.asset(
            'data/icons/title.png',
            height: 34,
            fit: BoxFit.contain,
          ),
        ),
        const Positioned(
          left: 22,
          top: 105,
          child: _MapControl(icon: Icons.add_rounded),
        ),
        const Positioned(
          left: 22,
          top: 143,
          child: _MapControl(icon: Icons.remove_rounded),
        ),
        Positioned(
          left: 62,
          right: 62,
          bottom: 54,
          child: _AdvertisingBanner(data: data),
        ),
        const Positioned(
          left: 8,
          right: 8,
          bottom: 7,
          child: _MapBottomNavigation(),
        ),
      ],
    );
  }
}

class _MapControl extends StatelessWidget {
  const _MapControl({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.90),
        border: Border.all(color: const Color(0xFFD4DCE8)),
      ),
      child: Icon(icon, color: WebColors.blue, size: 18),
    );
  }
}

class _MapBottomNavigation extends StatelessWidget {
  const _MapBottomNavigation();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebColors.red, width: 1.5),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Icon(Icons.tune, color: WebColors.blue, size: 17),
          Icon(Icons.layers_outlined, color: WebColors.blue, size: 17),
          Icon(Icons.star_border, color: WebColors.blue, size: 17),
          Icon(Icons.info_outline, color: WebColors.blue, size: 17),
          Icon(Icons.person_outline, color: WebColors.blue, size: 17),
        ],
      ),
    );
  }
}

class _PremiumPhonePreview extends StatelessWidget {
  const _PremiumPhonePreview({required this.data});

  final DiffusionPreviewData data;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF4F7FA),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 26, 16, 12),
            color: WebColors.blue,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PLAGE DES CONCHES',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'LONGEVILLE-SUR-MER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFDCE3EA)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'BAIGNADE SURVEILLÉE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _PremiumInfoLine(
                      icon: Icons.flag_outlined,
                      label: 'Drapeau vert',
                    ),
                    const _PremiumInfoLine(
                      icon: Icons.schedule_outlined,
                      label: 'Surveillance : 11h – 19h',
                    ),
                    const SizedBox(height: 8),
                    _AdvertisingBanner(data: data),
                    const SizedBox(height: 12),
                    const Text(
                      'PRÉVISIONS',
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Row(
                      children: [
                        Expanded(
                          child: _ForecastDay(day: 'LUN', value: '23°'),
                        ),
                        SizedBox(width: 5),
                        Expanded(
                          child: _ForecastDay(day: 'MAR', value: '24°'),
                        ),
                        SizedBox(width: 5),
                        Expanded(
                          child: _ForecastDay(day: 'MER', value: '22°'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumInfoLine extends StatelessWidget {
  const _PremiumInfoLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: WebColors.blue, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF4B5F97),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForecastDay extends StatelessWidget {
  const _ForecastDay({required this.day, required this.value});

  final String day;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            day,
            style: const TextStyle(
              color: WebColors.blue,
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          const Icon(Icons.wb_sunny_outlined, color: Colors.orange, size: 15),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: WebColors.blue,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvertisingBanner extends StatelessWidget {
  const _AdvertisingBanner({required this.data});

  final DiffusionPreviewData data;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.94),
            border: Border.all(color: WebColors.red, width: 1.4),
          ),
          child: _bannerContent(),
        ),
      ),
    );
  }

  Widget _bannerContent() {
    final bytes = data.bannerBytes;
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.contain);
    }

    final bannerUrl = data.bannerUrl?.trim() ?? '';
    if (bannerUrl.isNotEmpty) {
      return Image.network(
        bannerUrl,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _BannerPlaceholder(data: data),
      );
    }

    return _BannerPlaceholder(data: data);
  }
}

class _BannerPlaceholder extends StatelessWidget {
  const _BannerPlaceholder({required this.data});

  final DiffusionPreviewData data;

  @override
  Widget build(BuildContext context) {
    final name = data.advertiserName.trim().isEmpty
        ? 'VOTRE ÉTABLISSEMENT'
        : data.advertiserName.trim().toUpperCase();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFFFFF4E8), Colors.white]),
      ),
      child: Row(
        children: [
          _AdvertiserLogo(logoUrl: data.logoUrl),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebColors.blue,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'VOTRE VISUEL PUBLICITAIRE',
                  style: TextStyle(
                    color: WebColors.red,
                    fontSize: 8,
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

class _AdvertiserLogo extends StatelessWidget {
  const _AdvertiserLogo({required this.logoUrl});

  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim() ?? '';
    return SizedBox(
      width: 38,
      height: 38,
      child: url.isEmpty
          ? SvgPicture.asset(
              'data/icons/fire_red_icon.svg',
              fit: BoxFit.contain,
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => SvgPicture.asset(
                  'data/icons/fire_red_icon.svg',
                  fit: BoxFit.contain,
                ),
              ),
            ),
    );
  }
}
