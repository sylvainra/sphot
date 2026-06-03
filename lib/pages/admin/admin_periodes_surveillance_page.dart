import 'package:flutter/material.dart';

class AdminPeriodesSurveillancePage extends StatefulWidget {
  const AdminPeriodesSurveillancePage({super.key});

  @override
  State<AdminPeriodesSurveillancePage> createState() =>
      _AdminPeriodesSurveillancePageState();
}

class _AdminPeriodesSurveillancePageState
    extends State<AdminPeriodesSurveillancePage> {
  final List<_SurveillancePeriod> _periods = [];

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
  }

  void _deletePeriod(_SurveillancePeriod period) {
    setState(() {
      _periods.remove(period);
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color pageColor = Color(0xFF0891B2);

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
                    'DATES/HEURES DE SURVEILLANCE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: pageColor,
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
                          color: Colors.black,
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
                              icon: const Icon(Icons.add_rounded),
                              label: const Text(
                                'AJOUTER UNE PÉRIODE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: pageColor,
                                foregroundColor: Colors.white,
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
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: _periods.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Aucune période de surveillance créée.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _periods.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 6),
                                    itemBuilder: (context, index) {
                                      final period = _periods[index];

                                      return Container(
                                        height: 86,
                                        padding: const EdgeInsets.fromLTRB(
                                          10,
                                          6,
                                          10,
                                          5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.86),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                            color: pageColor,
                                            width: 1.6,
                                          ),
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
      color: pageColor,
      fontSize: 14,
      fontWeight: FontWeight.w900,
    ),
  ),

  const SizedBox(height: 4),

  Text(
    'DU ${_formatDate(period.startDate)} AU ${_formatDate(period.endDate)}',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: Colors.black,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  ),

  const SizedBox(height: 2),

  Text(
    'DE ${_formatTime(period.startHour)} À ${_formatTime(period.endHour)}',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: Colors.black,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  ),
],
  ),
),      
                                            Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                SizedBox(
                                                  height: 30,
                                                  width: 34,
                                                  child: IconButton(
                                                    onPressed: () =>
                                                        _openPeriodDialog(
                                                      period: period,
                                                    ),
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
                                                    onPressed: () =>
                                                        _deletePeriod(period),
                                                    padding: EdgeInsets.zero,
                                                    icon: const Icon(
                                                      Icons.delete_rounded,
                                                      color: Colors.red,
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
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.black,
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
                        color: Colors.black,
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

    if (name.isEmpty ||
        _startDate == null ||
        _endDate == null ||
        _startHour == null ||
        _endHour == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Merci de renseigner tous les champs.'),
        ),
      );
      return;
    }

    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La date de fin doit être après la date de début.'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      _SurveillancePeriod(
        id: widget.period?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        startDate: _startDate!,
        endDate: _endDate!,
        startHour: _startHour!,
        endHour: _endHour!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color pageColor = Color(0xFF0891B2);

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
          onPressed: _save,
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
    const Color pageColor = Color(0xFF0891B2);

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