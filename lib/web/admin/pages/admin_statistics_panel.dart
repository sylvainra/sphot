import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

class AdminStatisticsPanel extends StatefulWidget {
  final String territoireId;
  final VoidCallback onClose;

  const AdminStatisticsPanel({
    super.key,
    required this.territoireId,
    required this.onClose,
  });

  @override
  State<AdminStatisticsPanel> createState() => _AdminStatisticsPanelState();
}

class _AdminStatisticsPanelState extends State<AdminStatisticsPanel> {
  static const Color _blue = Color(0xFF1E3A8A);
  static const Color _red = Color(0xFFDC2626);
  static const Color _background = Color(0xFFF8FAFC);

  bool _isLoading = true;
  String? _errorMessage;
  List<_PublicClickStatistic> _statistics = const [];

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  @override
  void didUpdateWidget(covariant AdminStatisticsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.territoireId != widget.territoireId) {
      _loadStatistics();
    }
  }

  Future<void> _loadStatistics() async {
    final territoireId = widget.territoireId.trim();

    if (territoireId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Territoire Admin non identifié.';
        _statistics = const [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse(
              'https://europe-west1-sphot-ab80b.cloudfunctions.net/'
              'getPublicClickStats',
            ),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'territoireId': territoireId}),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Réponse ${response.statusCode}');
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic> || payload['success'] != true) {
        throw Exception('Réponse invalide');
      }

      final rawStatistics = payload['statistics'];
      final statistics = rawStatistics is List
          ? rawStatistics
              .whereType<Map>()
              .map(
                (value) => _PublicClickStatistic.fromJson(
                  Map<String, dynamic>.from(value),
                ),
              )
              .toList()
          : <_PublicClickStatistic>[];

      statistics.sort(
        (first, second) => second.totalClicks.compareTo(first.totalClicks),
      );

      if (!mounted) return;
      setState(() {
        _statistics = statistics;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Impossible de charger les statistiques pour le moment.';
      });
    }
  }

  int get _appTotal => _statistics.fold(
        0,
        (total, statistic) => total + statistic.appClicks,
      );

  int get _webTotal => _statistics.fold(
        0,
        (total, statistic) => total + statistic.webClicks,
      );

  int get _allTotal => _statistics.fold(
        0,
        (total, statistic) => total + statistic.totalClicks,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 430,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(
            color: _blue.withOpacity(0.45),
            width: 1.5,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Divider(
                height: 1,
                color: _blue.withOpacity(0.20),
              ),
              Expanded(
                child: Container(
                  color: _background,
                  child: _buildContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 6),
          Transform.translate(
            offset: const Offset(-12, -2),
            child: Transform.scale(
              scale: 1.5,
              alignment: Alignment.center,
              child: SvgPicture.asset(
                'data/icons/fire_red_icon.svg',
                width: 30,
                height: 30,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'STATISTIQUES',
              style: TextStyle(
                color: _blue,
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _isLoading ? null : _loadStatistics,
            icon: const Icon(
              Icons.refresh_rounded,
              color: _blue,
            ),
          ),
          IconButton(
            tooltip: 'Fermer',
            onPressed: widget.onClose,
            icon: const Icon(
              Icons.close_rounded,
              color: Color(0xFF374151),
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _blue),
      );
    }

    if (_errorMessage != null) {
      return _buildMessage(
        icon: Icons.cloud_off_rounded,
        title: 'STATISTIQUES INDISPONIBLES',
        message: _errorMessage!,
        showRefresh: true,
      );
    }

    if (_statistics.isEmpty) {
      return _buildMessage(
        icon: Icons.bar_chart_rounded,
        title: 'AUCUN CLIC ENREGISTRÉ',
        message:
            'Les ouvertures des SPHOTS et du SPHOT Admin apparaîtront ici '
            'après l’activation du comptage.',
        showRefresh: true,
      );
    }

    return RefreshIndicator(
      color: _blue,
      onRefresh: _loadStatistics,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'FRÉQUENTATION PUBLIQUE',
            style: TextStyle(
              color: _blue,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Nombre d’ouvertures enregistrées depuis l’activation du comptage.',
            style: TextStyle(
              color: _blue.withOpacity(0.72),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildTotalCard(
                  icon: Icons.phone_android_rounded,
                  title: 'APPLICATION',
                  value: _appTotal,
                  color: _red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTotalCard(
                  icon: Icons.language_rounded,
                  title: 'SITE WEB',
                  value: _webTotal,
                  color: _blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTotalCard(
                  icon: Icons.ads_click_rounded,
                  title: 'TOTAL',
                  value: _allTotal,
                  color: const Color(0xFF0F766E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'DÉTAIL PAR SPHOT',
            style: TextStyle(
              color: _blue,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          ..._statistics.map(_buildStatisticCard),
        ],
      ),
    );
  }

  Widget _buildTotalCard({
    required IconData icon,
    required String title,
    required int value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 7),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              maxLines: 1,
              style: const TextStyle(
                color: _blue,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _normalizeSpotType(String value) {
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

  String _statisticMarkerAsset(_PublicClickStatistic statistic) {
    if (statistic.targetType == 'admin' || statistic.isPosteSecours) {
      return 'data/icons/fire_red_icon.svg';
    }

    final type = _normalizeSpotType(statistic.typeSphot);

    if (type.contains('POSTE DE SECOURS')) {
      return 'data/icons/fire_red_icon.svg';
    }

    if (type.contains('NATURISME') || type.contains('NATURISTE')) {
      return 'data/icons/fire_skin_icon.svg';
    }

    if (type.contains('PLAGE')) {
      return 'data/icons/fire_orange_icon.svg';
    }

    if (type.contains('LAC') ||
        type.contains('ETANG') ||
        type.contains("PLAN D'EAU") ||
        type.contains('PLAN D EAU') ||
        type.contains('BARRAGE')) {
      return 'data/icons/fire_blue_icon.svg';
    }

    if (type.contains('FLEUVE') ||
        type.contains('RIVIERE') ||
        type.contains('CASCADE')) {
      return 'data/icons/fire_green_icon.svg';
    }

    if (type.contains('LAGON') || type.contains('PISCINE NATURELLE')) {
      return 'data/icons/fire_cyan_icon.svg';
    }

    return 'data/icons/fire_orange1_icon.svg';
  }

  Widget _buildStatisticCard(_PublicClickStatistic statistic) {
    final isAdmin = statistic.targetType == 'admin';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _blue.withOpacity(0.17),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 30,
                child: SvgPicture.asset(
                  _statisticMarkerAsset(statistic),
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statistic.targetName.isEmpty
                      ? (isAdmin ? 'SPHOT ADMIN' : 'SPHOT')
                      : statistic.targetName.toUpperCase(),
                  style: const TextStyle(
                    color: _blue,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCountLine(
            icon: Icons.phone_android_rounded,
            label: 'APPLICATION',
            value: statistic.appClicks,
            color: _red,
          ),
          const SizedBox(height: 7),
          _buildCountLine(
            icon: Icons.language_rounded,
            label: 'SITE WEB',
            value: statistic.webClicks,
            color: _blue,
          ),
          const Divider(height: 18),
          _buildCountLine(
            icon: Icons.ads_click_rounded,
            label: 'TOTAL',
            value: statistic.totalClicks,
            color: const Color(0xFF0F766E),
            emphasized: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCountLine({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
    bool emphasized = false,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: _blue.withOpacity(0.85),
              fontSize: 12,
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: emphasized ? 18 : 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String message,
    required bool showRefresh,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(icon, color: _blue, size: 54),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _blue,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _blue.withOpacity(0.72),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            if (showRefresh) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _loadStatistics,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('ACTUALISER'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _blue,
                  side: const BorderSide(color: _blue),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PublicClickStatistic {
  final String targetType;
  final String targetName;
  final String typeSphot;
  final bool isPosteSecours;
  final int appClicks;
  final int webClicks;
  final int totalClicks;

  const _PublicClickStatistic({
    required this.targetType,
    required this.targetName,
    required this.typeSphot,
    required this.isPosteSecours,
    required this.appClicks,
    required this.webClicks,
    required this.totalClicks,
  });

  factory _PublicClickStatistic.fromJson(Map<String, dynamic> json) {
    int readCount(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return _PublicClickStatistic(
      targetType: (json['targetType'] ?? '').toString(),
      targetName: (json['targetName'] ?? '').toString(),
      typeSphot: (json['typeSphot'] ?? '').toString(),
      isPosteSecours: json['isPosteSecours'] == true,
      appClicks: readCount(json['appClicks']),
      webClicks: readCount(json['webClicks']),
      totalClicks: readCount(json['totalClicks']),
    );
  }
}
