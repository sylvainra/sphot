import 'package:flutter/material.dart';

class LifeguardInfoPage extends StatefulWidget {
  const LifeguardInfoPage({super.key});

  @override
  State<LifeguardInfoPage> createState() => _LifeguardInfoPageState();
}

class _LifeguardInfoPageState extends State<LifeguardInfoPage> {
  String flagColor = 'Vert';
  String flagPosition = 'Hissé';
  String status = 'Baignade surveillée';

  void updateFlagPosition(String position) {
    setState(() {
      flagPosition = position;

      if (position == 'Affalé') {
        status = 'Baignade non surveillée temporairement';
      } else {
        status = 'Baignade surveillée';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isTemporaryClosed = flagPosition == 'Affalé';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FA),
      appBar: AppBar(
        title: const Text('Renseignements sauveteurs'),
        backgroundColor: const Color(0xFF003B5C),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (isTemporaryClosed) _dangerBanner(),

            _sectionCard(
              title: 'Infos du poste',
              icon: Icons.info_outline,
              children: const [
                _InfoLine(label: 'Spot / plage', value: 'LONGE 09'),
                _InfoLine(label: 'Statut', value: 'Baignade surveillée'),
                _InfoLine(label: 'Horaires', value: '09:00 - 19:00'),
                _InfoLine(label: 'Poste de secours', value: '04 00 00 00 00'),
              ],
            ),

            _sectionCard(
              title: 'Équipe de sauveteurs',
              icon: Icons.groups,
              children: const [
                _RescuerTile(
                  name: 'Jean Martin',
                  role: 'Chef de poste',
                  contact: 'Radio canal 1',
                ),
                _RescuerTile(
                  name: 'Laura Bernard',
                  role: 'Sauveteur',
                  contact: 'Radio canal 2',
                ),
              ],
            ),

            _sectionCard(
              title: 'Actions rapides',
              icon: Icons.flash_on,
              children: [
                _dropdownAction(
                  label: 'Couleur du drapeau',
                  value: flagColor,
                  items: const ['Vert', 'Jaune', 'Rouge'],
                  onChanged: (value) {
                    setState(() {
                      flagColor = value!;
                    });
                  },
                ),
                const SizedBox(height: 12),
                _dropdownAction(
                  label: 'Position du drapeau',
                  value: flagPosition,
                  items: const ['Hissé', 'Affalé'],
                  onChanged: (value) {
                    updateFlagPosition(value!);
                  },
                ),
                const SizedBox(height: 16),
                _ActionButton(
                  icon: Icons.warning_amber_rounded,
                  label: 'Déclarer un danger',
                  color: Colors.orange,
                  onTap: () {},
                ),
                _ActionButton(
                  icon: Icons.note_add,
                  label: 'Ajouter une note d’intervention',
                  color: Colors.blue,
                  onTap: () {},
                ),
                _ActionButton(
                  icon: Icons.phone,
                  label: 'Appeler les secours',
                  color: Colors.red,
                  onTap: () {},
                ),
              ],
            ),

            _sectionCard(
              title: 'Notes / consignes du jour',
              icon: Icons.assignment,
              children: const [
                _InfoLine(label: 'Météo terrestre', value: '24°C, vent faible'),
                _InfoLine(label: 'Météo maritime', value: 'Mer peu agitée'),
                _InfoLine(label: 'Marées', value: 'Basse : 08:42 / Haute : 15:10'),
                _InfoLine(label: 'Coefficient', value: '72'),
                _InfoLine(label: 'Courants', value: 'Courant latéral modéré'),
                _InfoLine(label: 'Pollution', value: 'Aucune pollution signalée'),
                _InfoLine(label: 'Méduses', value: 'Présence faible'),
                _InfoLine(label: 'Événement spécial', value: 'Cours de paddle à 14h'),
                _InfoLine(label: 'Message interne', value: 'Surveillance renforcée zone nord'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dangerBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.warning_rounded, color: Colors.white, size: 36),
          SizedBox(height: 8),
          Text(
            'BAIGNADE NON SURVEILLÉE TEMPORAIREMENT',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Baignade à vos risques et périls',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF003B5C)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003B5C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _dropdownAction({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          items: items
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(item),
                  ))
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF3F7FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

class _RescuerTile extends StatelessWidget {
  final String name;
  final String role;
  final String contact;

  const _RescuerTile({
    required this.name,
    required this.role,
    required this.contact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFF003B5C),
            child: Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(role),
                Text(contact, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}