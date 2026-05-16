import 'package:flutter/material.dart';
import 'package:numberpicker/numberpicker.dart';

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
                      color: Color(0xFF5D4037),
                      letterSpacing: 0.6,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFF5D4037),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'PRÉVISIONS',
                            style: TextStyle(
                              color: Color(0xFF5D4037),
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),

                          const SizedBox(height: 18),

                          SizedBox(
                            height: 320,
                            child: GridView.count(
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio: 1.35,
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              children: [
                                _WeatherPickerCard(
  title: 'AIR',
  icon: Icons.thermostat_rounded,
  minValue: airMin,
  maxValue: airMax,
  onMinChanged: (value) {
    setState(() => airMin = value);
  },
  onMaxChanged: (value) {
    setState(() => airMax = value);
  },
),

_WeatherSkyCard(),

const _WeatherInfoCard(
  title: 'UV',
  value: '7 / ÉLEVÉ',
  icon: Icons.wb_sunny_outlined,
),

const _WeatherInfoCard(
  title: 'VENT',
  value: '18 km/h',
  icon: Icons.air_rounded,
),

const _WeatherInfoCard(
  title: 'CANICULE',
  value: 'NIVEAU 0',
  icon: Icons.local_fire_department_rounded,
),

const _WeatherInfoCard(
  title: 'HUMIDITÉ',
  value: '62%',
  icon: Icons.water_drop_rounded,
),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Color(0xFF5D4037),
                      size: 24,
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

class _WeatherInfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _WeatherInfoCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.black,
          width: 2,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: const Color(0xFF5D4037),
            size: 34,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF5D4037),
              fontSize: 13,
              fontWeight: FontWeight.w900,
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
        color: Colors.white.withOpacity(0.94),
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
        color: Colors.white.withOpacity(0.94),
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

              const Text(
                'Matin',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
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

              const Text(
                'Après-midi',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
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