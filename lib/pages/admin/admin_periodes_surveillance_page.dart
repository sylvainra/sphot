import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class AdminPeriodesSurveillancePage extends StatefulWidget {
  final String ville;

  const AdminPeriodesSurveillancePage({
    super.key,
    this.ville = 'VILLE_NON_RENSEIGNEE',
  });

  @override
  State<AdminPeriodesSurveillancePage> createState() =>
      _AdminPeriodesSurveillancePageState();
}

class _AdminPeriodesSurveillancePageState
    extends State<AdminPeriodesSurveillancePage> {
  final List<_SurveillancePeriod> _periods = [];

  String _communeId() {
  return widget.ville
      .trim()
      .toUpperCase()
      .replaceAll(' ', '_')
      .replaceAll('-', '_')
      .replaceAll("'", '_');
}

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}h'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openPeriodDialog({_SurveillancePeriod? period}) async {
  final result = await showDialog<_SurveillancePeriod>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PeriodDialog(period: period),
  );

  if (result == null) return;

  setState(() {
    if (period == null) {
      _periods.add(result);
    } else {
      final index = _periods.indexOf(period);
      if (index != -1) {
        _periods[index] = result;
      }
    }
  });

  try {
  await FirebaseFirestore.instance
    .collection('communes')
.doc(_communeId())
.collection('periodesSurveillance')
.doc(result.id)
    .set({
    'id': result.id,
    'name': result.name.toUpperCase(),
    'ville': widget.ville.toUpperCase(),
    'startDate': Timestamp.fromDate(result.startDate),
    'endDate': Timestamp.fromDate(result.endDate),
    'startHour':
        '${result.startHour.hour.toString().padLeft(2, '0')}:${result.startHour.minute.toString().padLeft(2, '0')}',
    'endHour':
        '${result.endHour.hour.toString().padLeft(2, '0')}:${result.endHour.minute.toString().padLeft(2, '0')}',
    'label':
        '${result.name.toUpperCase()} — DU ${_formatDate(result.startDate)} AU ${_formatDate(result.endDate)} — DE ${_formatTime(result.startHour)} À ${_formatTime(result.endHour)}',
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  if (!mounted) return;

  
} catch (e) {
  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('ERREUR FIRESTORE : $e'),
    ),
  );
}
}

  Future<void> _deletePeriod(_SurveillancePeriod period) async {
  await FirebaseFirestore.instance
      .collection('communes')
      .doc(_communeId())
      .collection('periodesSurveillance')
      .doc(period.id)
      .delete();
}

  @override
  Widget build(BuildContext context) {
    const Color pageColor = Color(0xFF1E3A8A);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
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
                    'PÉRIODES DE SURVEILLANCE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFEF4444),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: pageColor,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: ElevatedButton.icon(
                              onPressed: () => _openPeriodDialog(),
                              icon: const Icon(
  Icons.add_rounded,
  color: Color(0xFFEF4444),
  size: 32,
),
                              label: const Text(
                                'AJOUTER UNE PÉRIODE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
  backgroundColor: Colors.transparent,
  shadowColor: Colors.transparent,
  foregroundColor: const Color(0xFF1E3A8A),
  side: const BorderSide(
    color: Color(0xFF1E3A8A),
    width: 2,
  ),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
  ),
),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'PÉRIODES EXISTANTES',
                              style: TextStyle(
                                color: pageColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          
                                        Expanded(
  child: StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('communes')
        .doc(_communeId())
        .collection('periodesSurveillance')
        .orderBy('startDate')
        .snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final docs = snapshot.data!.docs;

      if (docs.isEmpty) {
        return const Center(
          child: Text(
            'Aucune période de surveillance créée.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: pageColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }

      return ListView.separated(
        itemCount: docs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final doc = docs[index];
          final data = doc.data() as Map<String, dynamic>;

          final startDate = (data['startDate'] as Timestamp).toDate();
          final endDate = (data['endDate'] as Timestamp).toDate();

          final startParts = (data['startHour'] ?? '00:00').toString().split(':');
          final endParts = (data['endHour'] ?? '00:00').toString().split(':');

          final period = _SurveillancePeriod(
            id: doc.id,
            name: (data['name'] ?? '').toString(),
            startDate: startDate,
            endDate: endDate,
            startHour: TimeOfDay(
              hour: int.tryParse(startParts[0]) ?? 0,
              minute: int.tryParse(startParts.length > 1 ? startParts[1] : '0') ?? 0,
            ),
            endHour: TimeOfDay(
              hour: int.tryParse(endParts[0]) ?? 0,
              minute: int.tryParse(endParts.length > 1 ? endParts[1] : '0') ?? 0,
            ),
          );

          return Container(
            height: 100,
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 5),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: pageColor, width: 1.6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        period.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
  'DU ${_formatDate(period.startDate)}',
  style: const TextStyle(
    color: pageColor,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  ),
),
const SizedBox(height: 2),
Text(
  'AU ${_formatDate(period.endDate)}',
  style: const TextStyle(
    color: pageColor,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  ),
),
const SizedBox(height: 2),
Text(
  'DE ${_formatTime(period.startHour)} À ${_formatTime(period.endHour)}',
  style: const TextStyle(
    color: pageColor,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  ),
),
                    ],
                  ),
                                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 30,
                      width: 34,
                      child: IconButton(
                        onPressed: () => _openPeriodDialog(period: period),
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.edit_rounded,
                          color: pageColor,
                          size: 21,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 30,
                      width: 34,
                      child: IconButton(
                        onPressed: () async {
  await _deletePeriod(period);
},
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.delete_rounded,
                          color: Color(0xFFEF4444),
                          size: 21,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  ),
),
                                        
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: pageColor,
                        width: 2,
                      ),
                    ),
                    child: IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: pageColor,
                        size: 22,
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
}

class _PeriodDialog extends StatefulWidget {
  final _SurveillancePeriod? period;

  const _PeriodDialog({this.period});

  @override
  State<_PeriodDialog> createState() => _PeriodDialogState();
}

class _PeriodDialogState extends State<_PeriodDialog> {
  late final TextEditingController _nameController;
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _startHour;
  TimeOfDay? _endHour;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(
      text: widget.period?.name ?? '',
    );

    _startDate = widget.period?.startDate;
    _endDate = widget.period?.endDate;
    _startHour = widget.period?.startHour;
    _endHour = widget.period?.endHour;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Choisir';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return 'Choisir';
    return '${time.hour.toString().padLeft(2, '0')}h'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('fr', 'FR'),
      initialDate: isStart
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? _startDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startDate = picked;

        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (_startHour ?? const TimeOfDay(hour: 11, minute: 0))
          : (_endHour ?? const TimeOfDay(hour: 19, minute: 0)),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: true,
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startHour = picked;
      } else {
        _endHour = picked;
      }
    });
  }

  void _save() {
  final name = _nameController.text.trim();

  String missing = '';

  if (name.isEmpty) {
    missing = 'Nom de période manquant';
  } else if (_startDate == null) {
    missing = 'Date début manquante';
  } else if (_endDate == null) {
    missing = 'Date fin manquante';
  } else if (_startHour == null) {
    missing = 'Heure début manquante';
  } else if (_endHour == null) {
    missing = 'Heure fin manquante';
  } else if (_endDate!.isBefore(_startDate!)) {
    missing = 'La date de fin doit être après la date de début';
  }

  if (missing.isNotEmpty) {
    setState(() => _errorMessage = missing);
    return;
  }

  final period = _SurveillancePeriod(
    id: widget.period?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
    name: name,
    startDate: _startDate!,
    endDate: _endDate!,
    startHour: _startHour!,
    endHour: _endHour!,
  );

  Navigator.of(context).pop(period);
}

  @override
  Widget build(BuildContext context) {
    const Color pageColor = Color(0xFF1E3A8A);

    return AlertDialog(
      title: Text(
        widget.period == null ? 'Ajouter une période' : 'Modifier la période',
        style: const TextStyle(
          color: pageColor,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogButton(
              label: 'Date début',
              value: _formatDate(_startDate),
              icon: Icons.calendar_month_rounded,
              onTap: () => _pickDate(isStart: true),
            ),
            const SizedBox(height: 10),
            _DialogButton(
              label: 'Date fin',
              value: _formatDate(_endDate),
              icon: Icons.calendar_month_rounded,
              onTap: () => _pickDate(isStart: false),
            ),
            const SizedBox(height: 10),
            _DialogButton(
              label: 'Heure début',
              value: _formatTime(_startHour),
              icon: Icons.access_time_rounded,
              onTap: () => _pickTime(isStart: true),
            ),
            const SizedBox(height: 10),
            _DialogButton(
              label: 'Heure fin',
              value: _formatTime(_endHour),
              icon: Icons.access_time_rounded,
              onTap: () => _pickTime(isStart: false),
            ),
            TextField(
  controller: _nameController,
  textCapitalization: TextCapitalization.characters,
  decoration: const InputDecoration(
    labelText: 'Nom de la période',
    hintText: 'Ex : JUILLET-AOÛT',
  ),
),
const SizedBox(height: 14),
if (_errorMessage.isNotEmpty) ...[
  Text(
    _errorMessage,
    textAlign: TextAlign.center,
    style: const TextStyle(
      color: Color(0xFFEF4444),
      fontSize: 14,
      fontWeight: FontWeight.w900,
    ),
  ),
  const SizedBox(height: 10),
],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Annuler'),
        ),
        ElevatedButton(
  onPressed: () {
    setState(() {
      _errorMessage = 'BOUTON CLIQUÉ';
    });

    _save();
  },
  style: ElevatedButton.styleFrom(
    backgroundColor: pageColor,
    foregroundColor: Colors.white,
  ),
  child: const Text('Enregistrer'),
),
      ],
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _DialogButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color pageColor = Color(0xFF1E3A8A);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: pageColor,
            width: 1.6,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: pageColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurveillancePeriod {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final TimeOfDay startHour;
  final TimeOfDay endHour;

  const _SurveillancePeriod({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.startHour,
    required this.endHour,
  });
}