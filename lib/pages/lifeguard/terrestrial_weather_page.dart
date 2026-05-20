import 'package:flutter/material.dart';
import 'package:numberpicker/numberpicker.dart';

import 'dart:math';

import 'lifeguard_actions_page.dart';

class TerrestrialWeatherPage extends StatefulWidget {
  final Color profileColor;

  const TerrestrialWeatherPage({
    super.key,
    required this.profileColor,
  });

  @override
  State<TerrestrialWeatherPage> createState() =>
      _TerrestrialWeatherPageState();
}

class _TerrestrialWeatherPageState extends State<TerrestrialWeatherPage> {
  int airMin = 22;
  int airMax = 28;

  int uvIndex = 7;

  int heatwaveLevel = 1;

  String windDirectionMorning = 'O';
  String windDirectionEvening = 'NO';

  int windMorningSpeed = 10;
  int windEveningSpeed = 20;

  int gusts = 35;

  @override
Widget build(BuildContext context) {
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
                  'MÉTÉO TERRESTRE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFF0000),
                    letterSpacing: 0.6,
                  ),
                ),

                const SizedBox(height: 2),

                SizedBox(
  height: 497,
  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFF5D4037),
                        width: 2,
                      ),
                    ),
                    child: Transform.translate(
                      offset: const Offset(0, -4),
                      child: Column(
                        children: [
                          Transform.translate(
                            offset: const Offset(0, 6),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                'PRÉVISIONS',
                                style: TextStyle(
                                  color: Color(0xFF5D4037),
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 6),

                          Row(
                            children: [
                              Expanded(
                                child: _WeatherPickerCard(
                                  title: 'AIR',
                                  icon: Icons.thermostat_rounded,
                                  minValue: airMin,
                                  maxValue: airMax,
                                  onMinChanged: (value) {
                                    setState(() {
                                      airMin = value;
                                    });
                                  },
                                  onMaxChanged: (value) {
                                    setState(() {
                                      airMax = value;
                                    });
                                  },
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: _WeatherSkyCard(),
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          _WindFullWidthCard(
                            directionMorning: windDirectionMorning,
                            directionEvening: windDirectionEvening,
                            morningSpeed: windMorningSpeed,
                            eveningSpeed: windEveningSpeed,
                            gusts: gusts,
                            onDirectionMorningChanged: (value) {
                              setState(() {
                                windDirectionMorning = value;
                              });
                            },
                            onDirectionEveningChanged: (value) {
                              setState(() {
                                windDirectionEvening = value;
                              });
                            },
                            onMorningSpeedChanged: (value) {
                              setState(() {
                                windMorningSpeed = value;
                              });
                            },
                            onEveningSpeedChanged: (value) {
                              setState(() {
                                windEveningSpeed = value;
                              });
                            },
                            onGustsChanged: (value) {
                              setState(() {
                                gusts = value;
                              });
                            },
                          ),

                          const SizedBox(height: 6),

                          Expanded(
                            child: GridView.count(
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              childAspectRatio: 1.45,
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              children: [
                                _UVCard(
                                  uvIndex: uvIndex,
                                  onChanged: (value) {
                                    setState(() {
                                      uvIndex = value;
                                    });
                                  },
                                ),

                                _HeatwaveCard(
                                  level: heatwaveLevel,
                                  onChanged: (value) {
                                    setState(() {
                                      heatwaveLevel = value;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
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
                        border: Border.all(
                          color: Colors.black,
                          width: 2,
                        ),
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
    ),
  );
}

}

class _UVCard extends StatelessWidget {
  final int uvIndex;
  final ValueChanged<int> onChanged;

  const _UVCard({
    required this.uvIndex,
    required this.onChanged,
  });

  Color _uvColor(int value) {
    if (value <= 2) return const Color(0xFFD6D6D6);
    if (value <= 4) return const Color(0xFFD8CF9B);
    if (value <= 6) return const Color(0xFFE6DD3B);
    if (value <= 8) return const Color(0xFFF3EA00);
    return const Color(0xFFFFFF00);
  }

  String _uvLabel(int value) {
    if (value <= 2) return 'FAIBLE';
    if (value <= 4) return 'MODÉRÉ';
    if (value <= 6) return 'ÉLEVÉ';
    if (value <= 8) return 'TRÈS FORT';
    return 'EXTRÊME';
  }

  @override
  Widget build(BuildContext context) {
    final uvColor = _uvColor(uvIndex);

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: uvColor,
          width: 3,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.wb_sunny_rounded,
                color: Color(0xFFFDE047),
                size: 24,
              ),
              SizedBox(width: 5),
              Text(
                'UV',
                style: TextStyle(
                  color: Color(0xFFFDE047),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),

          Transform.translate(
            offset: const Offset(0, -2),
            child: NumberPicker(
              value: uvIndex,
              minValue: 1,
              maxValue: 12,
              itemWidth: 105,
              itemHeight: 15,
              textMapper: (numberText) {
                final value = int.parse(numberText);
                return '$value ${_uvLabel(value)}';
              },
              textStyle: const TextStyle(
                fontSize: 8,
                color: Colors.black38,
                fontWeight: FontWeight.w700,
              ),
              selectedTextStyle: TextStyle(
                color: uvColor,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherPickerCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final int minValue;
  final int maxValue;
  final ValueChanged<int> onMinChanged;
  final ValueChanged<int> onMaxChanged;

  const _WeatherPickerCard({
    required this.title,
    required this.icon,
    required this.minValue,
    required this.maxValue,
    required this.onMinChanged,
    required this.onMaxChanged,
  });

  Color _temperatureColor(int value) {

  if (value <= -5) {
    return const Color(0xFF0D47A1); // bleu polaire
  }

  if (value <= 0) {
    return const Color(0xFF1565C0); // bleu foncé
  }

  if (value <= 5) {
    return const Color(0xFF1E88E5); // bleu
  }

  if (value <= 10) {
    return const Color(0xFF42A5F5); // bleu clair
  }

  if (value <= 15) {
    return const Color(0xFF26A69A); // turquoise
  }

  if (value <= 20) {
    return const Color(0xFF43A047); // vert
  }

  if (value <= 25) {
    return const Color(0xFF7CB342); // vert chaud
  }

  if (value <= 30) {
    return const Color(0xFFFB8C00); // orange
  }

  if (value <= 35) {
    return const Color(0xFFF4511E); // orange rouge
  }

  if (value <= 40) {
    return const Color(0xFFE53935); // rouge
  }

  return const Color(0xFFB71C1C); // rouge extrême
}

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _temperatureColor(maxValue),
          width: 2,
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: _temperatureColor(minValue),
                size: 26,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: _temperatureColor(maxValue),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    const Text(
      'De',
      style: TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 17,
        height: 1.4,
      ),
    ),

const SizedBox(width: 2),

    Transform.translate(
      offset: const Offset(0, -3),
      child: NumberPicker(
        value: minValue,
        minValue: -10,
        maxValue: 50,
        itemWidth: 26,
        itemHeight: 18,
        textStyle: const TextStyle(
          fontSize: 9,
          color: Colors.grey,
        ),
        selectedTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: _temperatureColor(minValue),
        ),
        onChanged: onMinChanged,
      ),
    ),

const SizedBox(width: 8),

    const Text(
      'à',
      style: TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 17,
        height: 1.4,
      ),
    ),

    const SizedBox(width: 4),

    Transform.translate(
      offset: const Offset(0, -3),
      child: NumberPicker(
        value: maxValue,
        minValue: -10,
        maxValue: 50,
        itemWidth: 26,
        itemHeight: 18,
        textStyle: const TextStyle(
          fontSize: 9,
          color: Colors.grey,
        ),
        selectedTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: _temperatureColor(maxValue),
        ),
        onChanged: onMaxChanged,
      ),
    ),

    const Text(
      '°C',
      style: TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 17,
        height: 1.4,
        color: Color(0xFF5D4037),
      ),
    ),
  ],
),
        ],
      ),
    );
  }
}

class _WeatherSkyCard extends StatefulWidget {
  @override
  State<_WeatherSkyCard> createState() => _WeatherSkyCardState();
}

class _WeatherSkyCardState extends State<_WeatherSkyCard> {
  final List<String> emojis = [
    '❄️',
    '🌫️',
    '☀️',
    '🌤️',
    '⛅',
    '🌦️',
    '🌧️',
    '⛈️',
    '🥵',
  ];

  int morningIndex = 2;
  int afternoonIndex = 4;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF1E88E5),
          width: 2,
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'CIEL',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1E88E5),
            ),
          ),

          const SizedBox(height: 2),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 74,
                child: Text(
                  'Matin',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),

              const SizedBox(width: 6),

              SizedBox(
                width: 36,
                height: 30,
                child: ListWheelScrollView.useDelegate(
                  itemExtent: 26,
                  perspective: 0.003,
                  diameterRatio: 1.2,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (index) {
                    setState(() {
                      morningIndex = index;
                    });
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: emojis.length,
                    builder: (context, index) {
                      return Center(
                        child: Text(
                          emojis[index],
                          style: const TextStyle(fontSize: 20),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 2),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 74,
                child: Text(
                  'Après-midi',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),

              const SizedBox(width: 6),

              SizedBox(
                width: 36,
                height: 30,
                child: ListWheelScrollView.useDelegate(
                  itemExtent: 26,
                  perspective: 0.003,
                  diameterRatio: 1.2,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (index) {
                    setState(() {
                      afternoonIndex = index;
                    });
                  },
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: emojis.length,
                    builder: (context, index) {
                      return Center(
                        child: Text(
                          emojis[index],
                          style: const TextStyle(fontSize: 20),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WindFullWidthCard extends StatelessWidget {
  final String directionMorning;
  final String directionEvening;
  final int morningSpeed;
  final int eveningSpeed;
  final int gusts;

  final ValueChanged<String> onDirectionMorningChanged;
  final ValueChanged<String> onDirectionEveningChanged;
  final ValueChanged<int> onMorningSpeedChanged;
  final ValueChanged<int> onEveningSpeedChanged;
  final ValueChanged<int> onGustsChanged;

  const _WindFullWidthCard({
    required this.directionMorning,
    required this.directionEvening,
    required this.morningSpeed,
    required this.eveningSpeed,
    required this.gusts,
    required this.onDirectionMorningChanged,
    required this.onDirectionEveningChanged,
    required this.onMorningSpeedChanged,
    required this.onEveningSpeedChanged,
    required this.onGustsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gustColor = _windColor(gusts);

    return Container(
      width: double.infinity,
      height: 230,
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: gustColor,
          width: 3,
        ),
      ),
      child: Column(
        children: [
          Transform.translate(
            offset: const Offset(0, 4),
            child: const Text(
              'VENT',
              style: TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),

          const SizedBox(height: 2),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _WindCompassPicker(
                label: 'Matin',
                value: directionMorning,
                speed: morningSpeed,
                onChanged: onDirectionMorningChanged,
                onSpeedChanged: onMorningSpeedChanged,
              ),
              _WindCompassPicker(
                label: 'Après-midi',
                value: directionEvening,
                speed: eveningSpeed,
                onChanged: onDirectionEveningChanged,
                onSpeedChanged: onEveningSpeedChanged,
              ),
            ],
          ),

          Transform.translate(
            offset: const Offset(0, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Rafales à',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(width: 6),

                _SmallWindPicker(
                  value: gusts,
                  onChanged: onGustsChanged,
                ),

                const SizedBox(width: 6),

                const Text(
                  'km/h',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 13,
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

Color _windColor(int value) {
  if (value <= 10) return const Color(0xFF2E7D32);
  if (value <= 20) return const Color(0xFF7CB342);
  if (value <= 30) return const Color(0xFFFBC02D);
  if (value <= 40) return const Color(0xFFFB8C00);
  if (value <= 60) return const Color(0xFFE53935);
  if (value <= 80) return const Color(0xFF8E24AA);
  return const Color(0xFF4A148C);
}

class _WindCompassPicker extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int speed;
  final ValueChanged<int> onSpeedChanged;

  const _WindCompassPicker({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.speed,
    required this.onSpeedChanged,
  });

  static const List<String> directions = [
    'N',
    'NNE',
    'NE',
    'ENE',
    'E',
    'ESE',
    'SE',
    'SSE',
    'S',
    'SSO',
    'SO',
    'OSO',
    'O',
    'ONO',
    'NO',
    'NNO',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Transform.translate(
          offset: const Offset(0, -4),
          child: Text(
  label,
            style: TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),

        Transform.translate(
          offset: const Offset(0, 6),
          child: SizedBox(
            width: 132,
            height: 108,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NumberPicker(
                        value: speed,
                        minValue: 0,
                        maxValue: 150,
                        itemWidth: 34,
                        itemHeight: 20,
                        textStyle: const TextStyle(
                          fontSize: 8,
                          color: Colors.black38,
                        ),
                        selectedTextStyle: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: _windColor(speed),
                        ),
                        onChanged: onSpeedChanged,
                      ),

                      const SizedBox(width: 2),

                      const Text(
                        'km/h',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),

                ...List.generate(directions.length, (index) {
                  final angle =
                      (index * 22.5 - 90) * pi / 180;

                  final x = 52 * cos(angle);
                  final y = 52 * sin(angle);

                  final dir = directions[index];
                  final selected = dir == value;

                  return Transform.translate(
                    offset: Offset(x, y),
                    child: GestureDetector(
                      onTap: () => onChanged(dir),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.black
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.black,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          dir,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : Colors.black,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SmallWindPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _SmallWindPicker({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return NumberPicker(
      value: value,
      minValue: 0,
      maxValue: 150,
      step: 1,
      itemWidth: 44,
      itemHeight: 18,
      textStyle: const TextStyle(
        color: Colors.black38,
        fontSize: 9,
      ),
      selectedTextStyle: TextStyle(
        color: _windColor(value),
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
      onChanged: onChanged,
    );
  }
}

class _HeatwaveCard extends StatelessWidget {
  final int level;
  final ValueChanged<int> onChanged;

  const _HeatwaveCard({
    required this.level,
    required this.onChanged,
  });

  Color _heatwaveColor(int value) {
    switch (value) {
      case 1:
        return const Color(0xFF2FA354);
      case 2:
        return const Color(0xFFFFD426);
      case 3:
        return const Color(0xFFFF6F1A);
      case 4:
        return const Color(0xFFF92B3F);
      default:
        return const Color(0xFF2FA354);
    }
  }

  String _heatwaveTitle(int value) {
    switch (value) {
      case 1:
        return 'VEILLE\nSAISONNIÈRE';
      case 2:
        return 'AVERTISSEMENT\nCHALEUR';
      case 3:
        return 'ALERTE\nCANICULE';
      case 4:
        return 'MOBILISATION\nMAXIMALE';
      default:
        return 'VEILLE\nSAISONNIÈRE';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _heatwaveColor(level);

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color,
          width: 3,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 5),
              const Text(
                'CANICULE',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),

          Transform.translate(
            offset: const Offset(0, -8),
            child: NumberPicker(
              value: level,
              minValue: 1,
              maxValue: 4,
              itemWidth: 120,
              itemHeight: 15,
              textMapper: (numberText) {
                final value = int.parse(numberText);
                return 'NIVEAU $value';
              },
              textStyle: const TextStyle(
                fontSize: 8,
                color: Colors.black38,
                fontWeight: FontWeight.w700,
              ),
              selectedTextStyle: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
              onChanged: onChanged,
            ),
          ),

          Transform.translate(
            offset: const Offset(0, -10),
            child: Text(
              _heatwaveTitle(level),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}