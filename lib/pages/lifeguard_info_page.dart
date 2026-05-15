import 'package:flutter/material.dart';

class LifeguardInfoPage extends StatefulWidget {
  final Color profileColor;

  const LifeguardInfoPage({
    super.key,
    required this.profileColor,
  });

  @override
  State<LifeguardInfoPage> createState() => _LifeguardInfoPageState();
}

class _LifeguardInfoPageState extends State<LifeguardInfoPage> {
  String flagColor = 'Vert';
  String flagPosition = 'Hissé';
  String status = 'Baignade surveillée';

  String nomSecours = 'LONGE 09';
  String nomSphot = 'Le Rocher';
  String typeSphot = 'Poste de secours';

  bool isSphotMenuOpen = false;
  bool isDangerMenuOpen = false;

  final Set<String> selectedDangers = {};

  final List<String> dangerChoices = [
    '⚠️ COURANTS',
    '⚠️ BAÏNES',
    '🌊 SHORE BREAK',
    '🌊 VAGUES FORTES',
    '🌊 HOULE',
    '🟥 CONDITIONS DÉFAVORABLES DE VENT POUR CERTAINS ÉQUIPEMENTS NAUTIQUES',
    '☀️ CHÂLEURS',
    '☀️ CANICULE NIVEAU 1',
    '☀️ CANICULE NIVEAU 2',
    '☀️ CANICULE NIVEAU 3',
    '☀️ CANICULE NIVEAU 4',
    '🟪 ALTÉRATION DE LA QUALITÉ DES EAUX DE BAIGNADE',
    '🟪 PRÉSENCE D’ESPÈCES DANGEREUSES (MÉDUSES...)',
    '🟪 EXISTANCE D’UNE ZONE MARINE OU SOUS-MARINE PROTÉGÉE',
    '❄️ EAU FROIDE',
    '🪨 ROCHERS / RÉCIFS',
    '⚠️ DÉVERSEMENT',
    '⚠️ CRUE',
    '⚠️ FAIBLE PROFONDEUR',
    '⚠️ ASPIRATION',
    '🚤 ⛵ 🛥️ TRAFFIC MARITIME',
    '🌀 TOURBILLONS',
    '⚠️ REMOUS',
    '⚠️ VASE / SABLE MOUVANT',
    '⚠️ LÂCHER DE BARRAGE',
    '🐎 CHEVAUX',
    '⚠️ REQUINS SIGNALÉS',
    '⚠️ CONDITIONS MÉTÉOROLOGIQUES PROPICES À LA PRÉSENCE DE REQUINS',
    '⚠️ AUTRE',
    '⚠️ NON RENSEIGNÉ',
  ];

  final List<Map<String, String>> postesSecoursCommune = [
    {
      'nomSecours': 'LONGE 09',
      'nomSphot': 'Le Rocher',
      'typeSphot': 'Poste de secours',
    },
    {
      'nomSecours': 'LONGE 13',
      'nomSphot': 'Les Conches',
      'typeSphot': 'Poste de secours',
    },
  ];

  void updateFlagPosition(String position) {
    setState(() {
      flagPosition = position;
      status = position == 'Affalé'
          ? 'Baignade non surveillée temporairement'
          : 'Baignade surveillée';
    });
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final bool isTemporaryClosed = flagPosition == 'Affalé';

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
            child: Column(
              children: [
                const SizedBox(height: 2),

                Image.asset(
                  'data/icons/title.png',
                  height: 56,
                  fit: BoxFit.contain,
                ),

                Text(
                  'RENSEIGNEMENTS SAUVETEURS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: widget.profileColor,
                    letterSpacing: 0.6,
                  ),
                ),

                const SizedBox(height: 4),

                Expanded(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
    child: Column(
      children: [
                          _sectionCard(
                            title: 'Choix du sphot',
                            icon: Icons.place_rounded,
                            children: [
                              PopupMenuButton<Map<String, String>>(
                                offset: Offset.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                color: Colors.white.withOpacity(0.98),
                                elevation: 12,
                                constraints: BoxConstraints(
  minWidth: MediaQuery.of(context).size.width - 64,
  maxWidth: MediaQuery.of(context).size.width - 64,
),
                                onOpened: () {
                                  setState(() => isSphotMenuOpen = true);
                                },
                                onCanceled: () {
                                  setState(() => isSphotMenuOpen = false);
                                },
                                onSelected: (poste) {
                                  setState(() {
                                    nomSecours = poste['nomSecours']!;
                                    nomSphot = poste['nomSphot']!;
                                    typeSphot = poste['typeSphot']!;
                                    isSphotMenuOpen = false;
                                  });
                                },
                                itemBuilder: (context) {
                                  return postesSecoursCommune.map((poste) {
                                    final secours = poste['nomSecours']!;
                                    final sphot = poste['nomSphot']!;
                                    final bool selected = secours == nomSecours;

                                    return PopupMenuItem<Map<String, String>>(
                                      value: poste,
                                      padding: EdgeInsets.zero,
                                      child: _SphotMenuItem(
                                        title: '$secours - $sphot',
                                        color: widget.profileColor,
                                        selected: selected,
                                        showArrow: false,
                                        isOpen: false,
                                      ),
                                    );
                                  }).toList();
                                },
                                child: _SphotMenuItem(
                                  title: '$nomSecours - $nomSphot',
                                  color: widget.profileColor,
                                  selected: true,
                                  showArrow: true,
                                  isOpen: isSphotMenuOpen,
                                ),
                              ),
                            ],
                          ),

                          if (!isTemporaryClosed)
                            Container(
                              width: double.infinity,
                              height: 58,
                              margin: const EdgeInsets.only(top: 3, bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: flagColor == 'Vert'
                                    ? const Color(0xFF22C55E)
                                    : flagColor == 'Jaune'
                                        ? const Color(0xFFFDE047)
                                        : const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.black,
                                  width: 3,
                                ),
                              ),
                              child: Text(
                                flagColor == 'Vert'
                                    ? 'BAIGNADE SURVEILLÉE ET AUTORISÉE'
                                    : flagColor == 'Jaune'
                                        ? 'BAIGNADE SURVEILLÉE MAIS DANGEREUSE'
                                        : 'BAIGNADE INTERDITE',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: flagColor == 'Jaune'
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),

                          if (isTemporaryClosed) _dangerBanner(),

_sectionCard(
  title: 'Actions rapides',
                            icon: Icons.flash_on,
                            children: [
                              const Text(
                                'Couleur du drapeau',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),

                              const SizedBox(height: 8),

                              Row(
                                children: [
                                  _FlagColorButton(
                                    label: 'Vert',
                                    color: const Color(0xFF22C55E),
                                    selected: flagColor == 'Vert',
                                    onTap: () {
                                      setState(() => flagColor = 'Vert');
                                    },
                                  ),
                                  const SizedBox(width: 10),
                                  _FlagColorButton(
                                    label: 'Jaune',
                                    color: const Color(0xFFFDE047),
                                    selected: flagColor == 'Jaune',
                                    onTap: () {
                                      setState(() => flagColor = 'Jaune');
                                    },
                                  ),
                                  const SizedBox(width: 10),
                                  _FlagColorButton(
                                    label: 'Rouge',
                                    color: const Color(0xFFEF4444),
                                    selected: flagColor == 'Rouge',
                                    onTap: () {
                                      setState(() => flagColor = 'Rouge');
                                    },
                                  ),
                                ],
                              ),

                              const SizedBox(height: 5),

                              const Text(
                                'Position du drapeau',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),

                              const SizedBox(height: 5),

                              _FlagPositionSwitch(
                                isAffale: flagPosition == 'Affalé',
                                color: widget.profileColor,
                                onChanged: (isAffale) {
                                  updateFlagPosition(
                                    isAffale ? 'Affalé' : 'Hissé',
                                  );
                                },
                              ),

                              const SizedBox(height: 5),

_ActionButton(
  icon: Icons.warning_amber_rounded,
  label: selectedDangers.isEmpty
      ? 'Déclarer un danger'
      : '${selectedDangers.length} danger(s) sélectionné(s)',
  color: const Color(0xFFFDE047),
  onTap: () {
    setState(() {
      isDangerMenuOpen = !isDangerMenuOpen;
    });
  },
),

const SizedBox(height: 4),

_ActionButton(
  icon: Icons.notifications_active_rounded,
  label: 'Ajouter une notification',
  color: const Color(0xFF2563EB),
  onTap: () {},
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

          if (isDangerMenuOpen)
            GestureDetector(
              onTap: () {
                setState(() => isDangerMenuOpen = false);
              },
              child: Container(color: Colors.black.withOpacity(0.15)),
            ),

          if (isDangerMenuOpen)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: MediaQuery.of(context).size.width * 0.66,
              child: _dangerSidePanel(),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bottomNavBar(),
          ),
        ],
      ),
    );
  }

  Widget _dangerSidePanel() {
    return SafeArea(
      child: Material(
        elevation: 24,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(22),
          bottomLeft: Radius.circular(22),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.98),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              bottomLeft: Radius.circular(22),
            ),
            border: Border.all(
              color: Colors.black,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Text(
                'DANGERS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.profileColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 8),

              Expanded(
                child: ListView.builder(
                  itemCount: dangerChoices.length,
                  itemBuilder: (context, index) {
                    final danger = dangerChoices[index];
                    final bool selected = selectedDangers.contains(danger);

                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: selected,
                      activeColor: const Color(0xFFFDE047),
                      checkColor: Colors.black,
                      title: Text(
                        danger,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            selectedDangers.add(danger);
                          } else {
                            selectedDangers.remove(danger);
                          }
                        });
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => isDangerMenuOpen = false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.profileColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'VALIDER',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomNavBar() {
    return SafeArea(
      top: false,
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
  color: Colors.transparent,
),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _BottomLogoButton(
              icon: Icons.home_rounded,
              color: widget.profileColor,
              onTap: _goHome,
            ),
            _BottomLogoButton(
              icon: Icons.watch_later_rounded,
              color: widget.profileColor,
              onTap: () {},
            ),
            _BottomLogoButton(
              icon: Icons.groups_rounded,
              color: widget.profileColor,
              onTap: () {},
            ),
            _BottomLogoButton(
              icon: Icons.info_rounded,
              color: widget.profileColor,
              onTap: () {},
            ),
            _BottomLogoButton(
              icon: Icons.account_circle,
              color: widget.profileColor,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _dangerBanner() {
    return Container(
      width: double.infinity,
      height: 58,
      margin: const EdgeInsets.only(top: 3, bottom: 6),
      padding: const EdgeInsets.symmetric(
        vertical: 6,
        horizontal: 14,
      ),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black,
          width: 3,
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.warning_rounded,
            color: Colors.white,
            size: 20,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'BAIGNADE NON SURVEILLÉE TEMPORAIREMENT',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    height: 1,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'BAIGNADE À VOS RISQUES ET PÉRILS',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    height: 1,
                  ),
                ),
              ],
            ),
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
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
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
              Icon(icon, color: widget.profileColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: widget.profileColor,
                  ),
                ),
              ),
            ],
          ),
                    ...children,
                ],
      ),
    );
  }
}

class _SphotMenuItem extends StatelessWidget {
  final String title;
  final Color color;
  final bool selected;
  final bool showArrow;
  final bool isOpen;

  const _SphotMenuItem({
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
      margin: const EdgeInsets.only(bottom: 4),
      height: 46,
padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFF3F7FA) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? Colors.black : Colors.black12,
          width: selected ? 1.5 : 1,
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
                fontSize: 15,
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
                size: 28,
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomLogoButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BottomLogoButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(icon, color: color, size: 30),
      ),
    );
  }
}

class _FlagColorButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FlagColorButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 46,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Colors.black : Colors.transparent,
              width: selected ? 3 : 0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: label == 'Jaune' ? Colors.black : Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlagPositionSwitch extends StatelessWidget {
  final bool isAffale;
  final Color color;
  final ValueChanged<bool> onChanged;

  const _FlagPositionSwitch({
    required this.isAffale,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F7FA),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: isAffale ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: isAffale ? Colors.red : color,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(false),
                    child: Center(
                      child: Text(
                        'HISSÉ',
                        style: TextStyle(
                          color: isAffale ? Colors.black54 : Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(true),
                    child: Center(
                      child: Text(
                        'AFFALÉ',
                        style: TextStyle(
                          color: isAffale ? Colors.white : Colors.black54,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
  height: 46,
  width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor:
              color == const Color(0xFFFDE047) ? Colors.black : Colors.white,
          minimumSize: const Size(double.infinity, 46),
          maximumSize: const Size(double.infinity, 46),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}