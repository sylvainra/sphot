import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'widgets/sauveteur_adaptive_viewport.dart';

class SauveteurPlanningPage extends StatefulWidget {
  final Color profileColor;
  final String userRole;
  final String territoireId;
  final String sphotMode;
  final String sauveteurSessionToken;
  final List<String> postesAffectes;
  final String? initialSpotId;
  final bool canManageRestrictedOperationalData;

  const SauveteurPlanningPage({
    super.key,
    required this.profileColor,
    required this.userRole,
    required this.territoireId,
    required this.sphotMode,
    required this.sauveteurSessionToken,
    required this.postesAffectes,
    required this.initialSpotId,
    required this.canManageRestrictedOperationalData,
  });

  @override
  State<SauveteurPlanningPage> createState() => _SauveteurPlanningPageState();
}

class _SauveteurPlanningPageState extends State<SauveteurPlanningPage> {
  bool get canEdit => widget.canManageRestrictedOperationalData;

  bool get canPersist =>
      canEdit && widget.sphotMode.toUpperCase() == 'ON';

  late stt.SpeechToText _speech;

  bool _isListening = false;
  String? _listeningKey;

  final ScrollController _headerHorizontalController = ScrollController();
  final ScrollController _tableHorizontalController = ScrollController();
  final ScrollController _totalHorizontalController = ScrollController();

  bool _syncingScroll = false;
  bool planningEnregistre = false;

  final List<Map<String, String>> beachList = [];

String? selectedBeach;
String? selectedSpotId;

  bool isBeachMenuOpen = false;

  String? openPlanningCellKey;

  final TextEditingController hoursController =
      TextEditingController(text: '11h00 - 19h00');

  final TextEditingController work1Controller = TextEditingController(
    text: '10h30-13h00\n13h30-19h30',
  );

  final TextEditingController work2Controller =
      TextEditingController(text: '13h00-19h30');

  final TextEditingController work3Controller =
      TextEditingController(text: '10h30-19h30');

  final TextEditingController restController =
      TextEditingController(text: 'Repos');

  final List<String> roles = [
    'Chef de poste',
    'Adjoint chef de poste',
    ...List.generate(20, (index) => 'Sauveteur ${index + 1}'),
  ];

  late DateTime _selectedMonth;
  late List<_PlanningColumn> columns;
  late Map<String, TextEditingController> nameControllers;
  late Map<String, TextEditingController> controllers;

  @override
  void initState() {
    super.initState();

    _speech = stt.SpeechToText();

    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);

    columns = _generateMonthColumns(
      _selectedMonth.year,
      _selectedMonth.month,
    );

    controllers = {
      for (final role in roles)
        for (final col in columns)
          if (!col.isTotal) '$role-${col.key}': TextEditingController(),
    };

    nameControllers = {
      for (final role in roles) role: TextEditingController(),
    };

    _loadBeaches();

    void syncFrom(
      ScrollController source,
      List<ScrollController> targets,
    ) {
      if (_syncingScroll || !source.hasClients) return;

      _syncingScroll = true;
      for (final target in targets) {
        if (!target.hasClients) continue;
        final max = target.position.maxScrollExtent;
        final offset = source.offset.clamp(0.0, max).toDouble();
        if ((target.offset - offset).abs() > 0.5) {
          target.jumpTo(offset);
        }
      }
      _syncingScroll = false;
    }

    _headerHorizontalController.addListener(() {
      syncFrom(
        _headerHorizontalController,
        [_tableHorizontalController, _totalHorizontalController],
      );
    });

    _tableHorizontalController.addListener(() {
      syncFrom(
        _tableHorizontalController,
        [_headerHorizontalController, _totalHorizontalController],
      );
    });

    _totalHorizontalController.addListener(() {
      syncFrom(
        _totalHorizontalController,
        [_headerHorizontalController, _tableHorizontalController],
      );
    });

  }

  List<_PlanningColumn> _generateMonthColumns(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final List<_PlanningColumn> result = [];

    for (int day = 1; day <= lastDay; day++) {
      final date = DateTime(year, month, day);

      result.add(
        _PlanningColumn(
          key: 'day_$day',
          label:
              '$day ${_shortDay(date.weekday)}\n'
              '${month.toString().padLeft(2, '0')}/$year',
          date: date,
        ),
      );

      if (date.weekday == DateTime.sunday) {
        result.add(
          const _PlanningColumn(
            key: 'week_total',
            label: 'TOTAL',
            isTotal: true,
          ),
        );
      }
    }

    result.add(
      const _PlanningColumn(
        key: 'month_total',
        label: 'TOTAL\nMOIS',
        isTotal: true,
        isMonthTotal: true,
      ),
    );

    return result;
  }

  String _shortDay(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Lun';
      case DateTime.tuesday:
        return 'Mar';
      case DateTime.wednesday:
        return 'Mer';
      case DateTime.thursday:
        return 'Jeu';
      case DateTime.friday:
        return 'Ven';
      case DateTime.saturday:
        return 'Sam';
      case DateTime.sunday:
        return 'Dim';
      default:
        return '';
    }
  }

  Future<void> _loadBeaches() async {
  final snapshot = await FirebaseFirestore.instance
      .collection('territoires')
      .doc(widget.territoireId)
      .collection('spots')
      .where('typeSphot', isEqualTo: '🚨 POSTE DE SECOURS 🚨')
      .get();

  final assignedIds = widget.postesAffectes.toSet();

  final spots = snapshot.docs
      .where((doc) => assignedIds.contains(doc.id))
      .map((doc) {
    final data = doc.data();
    final nomSecours = (data['nomSecours'] ?? '').toString();
    final nomSphot = (data['nomSphot'] ?? '').toString();

    final label = [
      nomSecours,
      nomSphot,
    ].where((v) => v.trim().isNotEmpty).join(' - ');

    return {
      'id': doc.id,
      'label': label.isEmpty ? doc.id : label,
    };
  }).toList();

  spots.sort((a, b) => a['label']!.compareTo(b['label']!));

  setState(() {
  beachList
    ..clear()
    ..addAll(
      spots.map(
        (e) => {
          'id': e['id']!,
          'label': e['label']!,
        },
      ),
    );

  if (beachList.isNotEmpty) {
    final preferredId = widget.initialSpotId?.trim();
    final initialBeach = beachList.firstWhere(
      (spot) => spot['id'] == preferredId,
      orElse: () => beachList.first,
    );
    selectedBeach = initialBeach['label'];
    selectedSpotId = initialBeach['id'];
  } else {
    selectedBeach = null;
    selectedSpotId = null;
  }
});

  await _loadPlanning();
}

  @override
  void dispose() {
    hoursController.dispose();
    work1Controller.dispose();
    work2Controller.dispose();
    work3Controller.dispose();
    restController.dispose();

    _headerHorizontalController.dispose();
    _tableHorizontalController.dispose();
    _totalHorizontalController.dispose();

    for (final controller in controllers.values) {
      controller.dispose();
    }

    for (final controller in nameControllers.values) {
      controller.dispose();
    }

    _speech.stop();

    super.dispose();
  }

String get _planningMonthId {
  return '${_selectedMonth.year}-'
      '${_selectedMonth.month.toString().padLeft(2, '0')}';
}

  static const List<String> _monthNames = <String>[
    'JANVIER',
    'FÉVRIER',
    'MARS',
    'AVRIL',
    'MAI',
    'JUIN',
    'JUILLET',
    'AOÛT',
    'SEPTEMBRE',
    'OCTOBRE',
    'NOVEMBRE',
    'DÉCEMBRE',
  ];

  String get _selectedMonthLabel {
    return '${_monthNames[_selectedMonth.month - 1]} '
        '${_selectedMonth.year}';
  }

  void _disposeMonthControllers() {
    for (final controller in controllers.values) {
      controller.dispose();
    }

    for (final controller in nameControllers.values) {
      controller.dispose();
    }
  }

  void _rebuildMonthControllers(DateTime month) {
    _disposeMonthControllers();

    columns = _generateMonthColumns(month.year, month.month);

    controllers = {
      for (final role in roles)
        for (final col in columns)
          if (!col.isTotal) '$role-${col.key}': TextEditingController(),
    };

    nameControllers = {
      for (final role in roles) role: TextEditingController(),
    };
  }

  Future<void> _changeMonth(int delta) async {
    if (_isListening) {
      await _speech.stop();
    }

    final nextMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + delta,
    );

    setState(() {
      _isListening = false;
      _listeningKey = null;
      openPlanningCellKey = null;
      planningEnregistre = false;
      _selectedMonth = DateTime(nextMonth.year, nextMonth.month);
      _rebuildMonthControllers(_selectedMonth);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in <ScrollController>[
        _headerHorizontalController,
        _tableHorizontalController,
        _totalHorizontalController,
      ]) {
        if (controller.hasClients) {
          controller.jumpTo(0);
        }
      }
    });

    await _loadPlanning();
  }

  Future<void> _goToCurrentMonth() async {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);

    if (_selectedMonth.year == current.year &&
        _selectedMonth.month == current.month) {
      return;
    }

    if (_isListening) {
      await _speech.stop();
    }

    setState(() {
      _isListening = false;
      _listeningKey = null;
      openPlanningCellKey = null;
      planningEnregistre = false;
      _selectedMonth = current;
      _rebuildMonthControllers(_selectedMonth);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in <ScrollController>[
        _headerHorizontalController,
        _tableHorizontalController,
        _totalHorizontalController,
      ]) {
        if (controller.hasClients) {
          controller.jumpTo(0);
        }
      }
    });

    await _loadPlanning();
  }

  Widget _monthNavigation() {
    final now = DateTime.now();
    final isCurrentMonth =
        _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.black,
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Mois précédent',
            visualDensity: VisualDensity.compact,
            onPressed: () => _changeMonth(-1),
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: Color(0xFF1E3A8A),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: isCurrentMonth ? null : _goToCurrentMonth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _selectedMonthLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (!isCurrentMonth)
                    const Text(
                      'Toucher pour revenir au mois actuel',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Mois suivant',
            visualDensity: VisualDensity.compact,
            onPressed: () => _changeMonth(1),
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF1E3A8A),
            ),
          ),
        ],
      ),
    );
  }

Future<void> _loadPlanning() async {
  if (selectedSpotId == null) return;

  setState(() {
    planningEnregistre = false;
    for (final controller in controllers.values) {
      controller.clear();
    }
    for (final controller in nameControllers.values) {
      controller.clear();
    }
  });

  final doc = await FirebaseFirestore.instance
      .collection('territoires')
      .doc(widget.territoireId)
      .collection('spots')
      .doc(selectedSpotId)
      .collection('planningSauveteurs')
      .doc(_planningMonthId)
      .get();

  if (!doc.exists) return;

  final data = doc.data() ?? {};
  final cells = Map<String, dynamic>.from(data['cells'] ?? {});
  final names = Map<String, dynamic>.from(data['names'] ?? {});

  setState(() {
    for (final entry in cells.entries) {
      controllers[entry.key]?.text = entry.value.toString();
    }

    for (final entry in names.entries) {
      nameControllers[entry.key]?.text = entry.value.toString();
    }

    hoursController.text = (data['openingHours'] ?? hoursController.text).toString();
  });
}

Future<void> _savePlanning() async {
  if (selectedSpotId == null || !canPersist) return;

  final cells = <String, String>{};
  for (final entry in controllers.entries) {
    cells[entry.key] = entry.value.text;
  }

  final names = <String, String>{};
  for (final entry in nameControllers.entries) {
    names[entry.key] = entry.value.text;
  }

  final uri = Uri.parse(
    'https://us-central1-sphot-ab80b.cloudfunctions.net/saveSauveteurPlanning',
  );

  final response = await http.post(
    uri,
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({
      'sauveteurSessionToken': widget.sauveteurSessionToken,
      'spotId': selectedSpotId,
      'spotLabel': selectedBeach,
      'monthId': _planningMonthId,
      'openingHours': hoursController.text,
      'cells': cells,
      'names': names,
    }),
  );

  if (!mounted) return;

  if (response.statusCode < 200 || response.statusCode >= 300) {
    setState(() {
      planningEnregistre = false;
    });
    return;
  }

  setState(() {
    planningEnregistre = true;
  });

  await Future.delayed(const Duration(seconds: 1));

  if (!mounted) return;

  setState(() {
    planningEnregistre = false;
  });
}

  Future<void> _listenToCell(
    String key,
    TextEditingController controller,
  ) async {
    if (!canEdit) return;

    if (_isListening && _listeningKey == key) {
      setState(() {
        _isListening = false;
        _listeningKey = null;
      });

      await _speech.stop();
      return;
    }

    final bool available = await _speech.initialize();
    if (!available) return;

    setState(() {
      _isListening = true;
      _listeningKey = key;
    });

    _speech.listen(
      localeId: 'fr_FR',
      onResult: (result) {
        setState(() {
          if (key == 'hours') {
  controller.text = result.recognizedWords;
} else {
  controller.text = result.recognizedWords;
}
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: controller.text.length),
          );
        });
      },
    );
  }

  double _hoursFromText(String value) {
    final text = value.toLowerCase().replaceAll(' ', '');

    if (text.contains('repos') || text.isEmpty) return 0;

    final regex = RegExp(
      r'(\d{1,2})h?(\d{0,2})-(\d{1,2})h?(\d{0,2})',
    );

    final matches = regex.allMatches(text);
    double total = 0;

    for (final match in matches) {
      final startHour = int.tryParse(match.group(1) ?? '') ?? 0;
      final startMinute = int.tryParse(match.group(2) ?? '0') ?? 0;
      final endHour = int.tryParse(match.group(3) ?? '') ?? 0;
      final endMinute = int.tryParse(match.group(4) ?? '0') ?? 0;

      final start = startHour + startMinute / 60;
      final end = endHour + endMinute / 60;

      if (end > start) {
        total += end - start;
      }
    }

    return total;
  }

  double _weekTotalForRole(String role, int totalColumnIndex) {
    double total = 0;

    for (int i = totalColumnIndex - 1; i >= 0; i--) {
      final col = columns[i];

      if (col.isTotal) break;

      final controller = controllers['$role-${col.key}'];

      if (controller != null) {
        total += _hoursFromText(controller.text);
      }
    }

    return total;
  }

  double _monthTotalForRole(String role) {
    double total = 0;

    for (final col in columns) {
      if (col.isTotal) continue;

      final controller = controllers['$role-${col.key}'];

      if (controller != null) {
        total += _hoursFromText(controller.text);
      }
    }

    return total;
  }

  int _workersForColumn(_PlanningColumn column) {
    if (column.isTotal) return 0;

    int total = 0;

    for (final role in roles) {
      final controller = controllers['$role-${column.key}'];

      if (controller == null) continue;

      final value = controller.text.toLowerCase();

      if (value.isEmpty) continue;
      if (value.contains('repos')) continue;

      total++;
    }

    return total;
  }

  String _formatHours(double value) {
    if (value == 0) return '-';

    if (value == value.roundToDouble()) {
      return '${value.toInt()}h';
    }

    final hours = value.floor();
    final minutes = ((value - hours) * 60).round();

    return '${hours}h${minutes.toString().padLeft(2, '0')}';
  }

  Color _templateColor(String value) {
    if (value == work1Controller.text) return const Color(0xFF66BB6A);
    if (value == work2Controller.text) return const Color(0xFF42A5F5);
    if (value == work3Controller.text) return const Color(0xFFFFA726);
    if (value == restController.text) return const Color(0xFFBDBDBD);

    return Colors.white.withOpacity(0.35);
  }

  Color _roleBackground(int index) {
    if (index == 0) {
      return const Color(0xFFFFD54F).withOpacity(0.45);
    }

    if (index == 1) {
      return const Color(0xFF64B5F6).withOpacity(0.35);
    }

    return Colors.white.withOpacity(0.20);
  }

  Color _columnBackground(_PlanningColumn col) {
    if (col.isTotal) {
      return const Color(0xFFFF8A80).withOpacity(0.82);
    }

    if (col.date?.weekday == DateTime.saturday) {
      return const Color(0xFF90CAF9).withOpacity(0.45);
    }

    if (col.date?.weekday == DateTime.sunday) {
      return const Color(0xFFFFAB91).withOpacity(0.45);
    }

    return Colors.white.withOpacity(0.35);
  }

  Widget _templateBox({
    required String label,
    required TextEditingController controller,
  }) {
    final Color baseColor = _templateColor(controller.text);

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: baseColor.withOpacity(0.78),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black, width: 1.4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (label.isNotEmpty)
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            Expanded(
              child: Center(
                child: TextField(
                  controller: controller,
                  readOnly: !canEdit,
                  textAlign: TextAlign.center,
                  maxLines: controller == restController ? 1 : 2,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topField({
    required TextEditingController controller,
    required IconData icon,
    required String keyName,
  }) {
    final listening = _isListening && _listeningKey == keyName;

    return Expanded(
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFFF0000), size: 18),
            const SizedBox(width: 2),
            Expanded(
  child: Row(
    children: [
      const Text(
        'Horaires d\'ouvertures: ',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: Colors.black,
        ),
      ),

      Expanded(
        child: TextField(
          controller: controller,
          readOnly: !canEdit,
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
          ),
        ),
      ),
    ],
  ),
),
            GestureDetector(
              onTap: keyName == 'hours'
    ? () => _listenToCell(keyName, controller)
    : null,
              child: Icon(
                listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: const Color(0xFFFF0000),
                size: 19,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text, double width, Color color) {
    return Container(
      width: width,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }

  Widget _roleCell(String role, int index) {
    final controller = nameControllers[role]!;
    final keyName = 'name_$role';
    final listening = _isListening && _listeningKey == keyName;

    return Container(
      width: 135,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _roleBackground(index),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    role,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                TextField(
                  controller: controller,
                  readOnly: !canEdit,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: () => _listenToCell(keyName, controller),
            child: Icon(
              listening ? Icons.mic_rounded : Icons.mic_none_rounded,
              color: const Color(0xFFFF0000),
              size: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalCell(String role, int index, _PlanningColumn col) {
    final total = col.isMonthTotal
        ? _monthTotalForRole(role)
        : _weekTotalForRole(role, index);

    return Container(
      width: col.isMonthTotal ? 88 : 70,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFF8A80).withOpacity(0.82),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Text(
        _formatHours(total),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _editableCell(String role, _PlanningColumn col) {
  final key = '$role-${col.key}';
  final controller = controllers[key]!;

  final List<String> choices = [
    work1Controller.text,
    work2Controller.text,
    work3Controller.text,
    restController.text,
  ];

  final selectedValue = choices.contains(controller.text)
      ? controller.text
      : '-';

  return PopupMenuButton<String>(
    offset: Offset.zero,
    position: PopupMenuPosition.under,
    enabled: canEdit,
    color: Colors.white.withOpacity(0.98),
    elevation: 10,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    ),
    constraints: const BoxConstraints(
      minWidth: 82,
      maxWidth: 82,
    ),
    onOpened: () {
      setState(() {
        openPlanningCellKey = key;
      });
    },
    onCanceled: () {
      setState(() {
        openPlanningCellKey = null;
      });
    },
    onSelected: (value) {
      setState(() {
        controller.text = value;
        openPlanningCellKey = null;
      });
    },
    itemBuilder: (context) {
      return choices.map((value) {
        final bool selected = value == controller.text;

        return PopupMenuItem<String>(
          value: value,
          padding: EdgeInsets.zero,
          child: _PlanningCellMenuItem(
            title: value,
            color: _templateColor(value),
            selected: selected,
          ),
        );
      }).toList();
    },
    child: _PlanningCellMenuItem(
      title: selectedValue,
      color: _templateColor(controller.text),
      selected: true,
      compact: true,
      isOpen: openPlanningCellKey == key,
    ),
  );
}

  Widget _scheduleTable() {
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: Row(
            children: [
              _headerCell(
                'Fonction',
                135,
                Colors.white.withOpacity(0.45),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _headerHorizontalController,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Row(
                    children: [
                      for (final col in columns)
                        _headerCell(
                          col.label,
                          col.isMonthTotal
                              ? 88
                              : col.isTotal
                                  ? 70
                                  : 82,
                          _columnBackground(col),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    for (int i = 0; i < roles.length; i++)
                      _roleCell(roles[i], i),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _tableHorizontalController,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      children: [
                        for (int i = 0; i < roles.length; i++)
                          Row(
                            children: [
                              for (int columnIndex = 0;
                                  columnIndex < columns.length;
                                  columnIndex++)
                                columns[columnIndex].isTotal
                                    ? _totalCell(
                                        roles[i],
                                        columnIndex,
                                        columns[columnIndex],
                                      )
                                    : _editableCell(
                                        roles[i],
                                        columns[columnIndex],
                                      ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _totalWorkersBar() {
    const totalRowColor = Color(0xFFFF8A80);

    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Container(
            width: 135,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: totalRowColor.withOpacity(0.82),
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: const Text(
              'TOTAL\nSAUVETEURS',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _totalHorizontalController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  for (final col in columns)
                    Container(
                      width: col.isMonthTotal
                          ? 88
                          : col.isTotal
                              ? 70
                              : 82,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: totalRowColor.withOpacity(0.82),
                        border: Border.all(
                          color: Colors.black,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        col.isTotal ? '-' : '${_workersForColumn(col)}',
                        style: const TextStyle(
                          fontSize: 15,
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
    );
  }

  Widget _beachDropdown() {
  return Expanded(
    child: PopupMenuButton<String>(
      offset: Offset.zero,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      color: Colors.white.withOpacity(0.98),
      elevation: 12,
      constraints: BoxConstraints(
  minWidth: MediaQuery.of(context).size.width - 56,
  maxWidth: MediaQuery.of(context).size.width - 56,
),
      enabled: canEdit,
      onOpened: () {
        setState(() => isBeachMenuOpen = true);
      },
      onCanceled: () {
        setState(() => isBeachMenuOpen = false);
      },
      onSelected: (beach) async {

  final selected = beachList.firstWhere(
    (e) => e['label'] == beach,
  );

  setState(() {
    selectedBeach = selected['label'];
    selectedSpotId = selected['id'];
    isBeachMenuOpen = false;
  });

  await _loadPlanning();
},
      itemBuilder: (context) {
        return beachList.map((spot) {

  final beach = spot['label']!;
          final bool selected = beach == selectedBeach;

          return PopupMenuItem<String>(
            value: beach,
            padding: EdgeInsets.zero,
            child: _PlanningBeachMenuItem(
              title: beach,
              color: const Color(0xFFFF0000),
              selected: selected,
              showArrow: false,
              isOpen: false,
            ),
          );
        }).toList();
      },
      child: SizedBox(
  height: 42,
  child: _PlanningBeachMenuItem(
    title: selectedBeach ?? 'Choisir un poste',
    color: const Color(0xFFFF0000),
    selected: true,
    showArrow: canEdit,
    isOpen: isBeachMenuOpen,
  ),
),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: SauveteurAdaptiveViewport(
        child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'data/images/map_background.jpg',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Image.asset(
                    'data/icons/title.png',
                    height: 56,
                    fit: BoxFit.contain,
                  ),
                  const Text(
                    'EMPLOI DU TEMPS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFF0000),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _topField(
                                controller: hoursController,
                                icon: Icons.access_time_rounded,
                                keyName: 'hours',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _templateBox(
                                label: 'Horaires de travail 1',
                                controller: work1Controller,
                              ),
                              const SizedBox(width: 6),
                              _templateBox(
                                label: 'Horaires de travail 2',
                                controller: work2Controller,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _templateBox(
                                label: 'Horaires de travail 3',
                                controller: work3Controller,
                              ),
                              const SizedBox(width: 6),
                              _templateBox(
                                label: '',
                                controller: restController,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _monthNavigation(),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.black,
                                  width: 2,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: _scheduleTable(),
                                  ),
                                  _totalWorkersBar(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

const SizedBox(height: 8),

SizedBox(
  width: double.infinity,
  height: 46,
  child: ElevatedButton.icon(
    onPressed: canPersist ? _savePlanning : null,
    icon: Icon(
      planningEnregistre
          ? Icons.check_rounded
          : canPersist
              ? Icons.save_rounded
              : Icons.visibility_rounded,
      color: planningEnregistre ? Colors.white : const Color(0xFFFF0000),
      size: 20,
    ),
    label: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        planningEnregistre
            ? 'PLANNING ENREGISTRÉ'
            : canPersist
                ? 'ENREGISTRER LE PLANNING'
                : canEdit
                    ? 'TEST NON ENREGISTRÉ'
                    : 'PLANNING EN CONSULTATION',
        maxLines: 1,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 14,
          color: planningEnregistre ? Colors.white : const Color(0xFFFF0000),
        ),
      ),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor:
          planningEnregistre ? const Color(0xFFFF0000) : Colors.transparent,
      foregroundColor:
          planningEnregistre ? Colors.white : const Color(0xFFFF0000),
      disabledBackgroundColor: Colors.transparent,
      elevation: 0,
      side: const BorderSide(
        color: Color(0xFFFF0000),
        width: 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  ),
),

                  Transform.translate(
                    offset: const Offset(0, 9),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.black,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      )),
    );
  }
}

class _PlanningBeachMenuItem extends StatelessWidget {
  final String title;
  final Color color;
  final bool selected;
  final bool showArrow;
  final bool isOpen;

  const _PlanningBeachMenuItem({
    required this.title,
    required this.color,
    required this.selected,
    required this.showArrow,
    required this.isOpen,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      margin: EdgeInsets.zero,
      height: 41,
padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
decoration: BoxDecoration(
  color: Colors.white.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? Colors.black : Colors.black12,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.place_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (showArrow)
            AnimatedRotation(
              turns: isOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: color,
                size: 22,
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanningCellMenuItem extends StatelessWidget {
  final String title;
  final Color color;
  final bool selected;
  final bool compact;
  final bool isOpen;

  const _PlanningCellMenuItem({
    required this.title,
    required this.color,
    required this.selected,
    this.compact = false,
    this.isOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 82,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.72),
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: selected ? Colors.black : Colors.black26,
          width: selected ? 1.3 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
                height: 1,
                color: Colors.black,
              ),
            ),
          ),
          if (compact)
            AnimatedRotation(
              turns: isOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 160),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.black,
                size: 14,
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanningColumn {
  final String key;
  final String label;
  final DateTime? date;
  final bool isTotal;
  final bool isMonthTotal;

  const _PlanningColumn({
    required this.key,
    required this.label,
    this.date,
    this.isTotal = false,
    this.isMonthTotal = false,
  });
}