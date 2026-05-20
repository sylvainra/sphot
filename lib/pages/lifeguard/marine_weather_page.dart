import 'dart:math';

import 'package:flutter/material.dart';
import 'package:numberpicker/numberpicker.dart';


class MarineWeatherPage extends StatefulWidget {
  final Color profileColor;

  const MarineWeatherPage({
    super.key,
    required this.profileColor,
  });

  @override
  State<MarineWeatherPage> createState() => _MarineWeatherPageState();
}

class _MarineWeatherPageState extends State<MarineWeatherPage> {
  int waterMin = 18;
  int waterMax = 22;

  int seaStateIndex = 3;

  int highTideHour1 = 6;
  int highTideMinute1 = 42;
  int highTideHour2 = 19;
  int highTideMinute2 = 05;
  int highTideCoef = 75;

  int lowTideHour1 = 0;
  int lowTideMinute1 = 35;
  int lowTideHour2 = 13;
  int lowTideMinute2 = 12;
  int lowTideCoef = 72;

  String swellDirectionMorning = 'O';
  String swellDirectionAfternoon = 'NO';

  int swellMorningHeight = 1;
  int swellMorningDecimal = 2;

  int swellAfternoonHeight = 1;
  int swellAfternoonDecimal = 6;

  int periodMin = 8;
  int periodMax = 12;

  @override
Widget build(BuildContext context) {
  final tideColor = _tideColor(highTideCoef);

  final swellColor = _swellColor(
    max(
      swellMorningHeight * 10 + swellMorningDecimal,
      swellAfternoonHeight * 10 + swellAfternoonDecimal,
    ),
  );

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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),

            child: Column(
              children: [
                Image.asset(
                  'data/icons/title.png',
                  height: 56,
                  fit: BoxFit.contain,
                ),

                const Text(
                  'MÉTÉO MARINE',
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
  height: 500,
  child: Container(
    width: double.infinity,

    padding: const EdgeInsets.fromLTRB(
      16,
      0,
      16,
      0,
    ),

    decoration: BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),

      border: Border.all(
        color: Colors.black,
        width: 2,
      ),
    ),

    child: Transform.translate(
      offset: const Offset(0, -12),

      child: Column(
        children: [
          Transform.translate(
            offset: const Offset(0, 10),

            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),

              child: Text(
                'PRÉVISIONS',

                style: TextStyle(
                  color: Color(0xFF0277BD),
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
                child: SizedBox(
                  height: 92,

                  child: _WaterTemperatureCard(
                    minValue: waterMin,
                    maxValue: waterMax,

                    onMinChanged: (value) {
                      setState(() {
                        waterMin = value;
                      });
                    },

                    onMaxChanged: (value) {
                      setState(() {
                        waterMax = value;
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: SizedBox(
                  height: 92,

                  child: _SeaStateCard(
                    value: seaStateIndex,

                    onChanged: (value) {
                      setState(() {
                        seaStateIndex = value;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),

          Transform.translate(
            offset: const Offset(0, 6),

            child: _TidesFullWidthCard(
              borderColor: tideColor,

              highHour1: highTideHour1,
              highMinute1: highTideMinute1,
              highHour2: highTideHour2,
              highMinute2: highTideMinute2,
              highCoef: highTideCoef,

              lowHour1: lowTideHour1,
              lowMinute1: lowTideMinute1,
              lowHour2: lowTideHour2,
              lowMinute2: lowTideMinute2,
              lowCoef: lowTideCoef,

              onHighHour1Changed: (value) {
                setState(() {
                  highTideHour1 = value;
                });
              },

              onHighMinute1Changed: (value) {
                setState(() {
                  highTideMinute1 = value;
                });
              },

              onHighHour2Changed: (value) {
                setState(() {
                  highTideHour2 = value;
                });
              },

              onHighMinute2Changed: (value) {
                setState(() {
                  highTideMinute2 = value;
                });
              },

              onHighCoefChanged: (value) {
                setState(() {
                  highTideCoef = value;
                });
              },

              onLowHour1Changed: (value) {
                setState(() {
                  lowTideHour1 = value;
                });
              },

              onLowMinute1Changed: (value) {
                setState(() {
                  lowTideMinute1 = value;
                });
              },

              onLowHour2Changed: (value) {
                setState(() {
                  lowTideHour2 = value;
                });
              },

              onLowMinute2Changed: (value) {
                setState(() {
                  lowTideMinute2 = value;
                });
              },

              onLowCoefChanged: (value) {
                setState(() {
                  lowTideCoef = value;
                });
              },
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            height: 225,

            child: ClipRect(
  child: _SwellFullWidthCard(
              borderColor: swellColor,

              directionMorning:
                  swellDirectionMorning,

              directionAfternoon:
                  swellDirectionAfternoon,

              morningHeight:
                  swellMorningHeight,

              morningDecimal:
                  swellMorningDecimal,

              afternoonHeight:
                  swellAfternoonHeight,

              afternoonDecimal:
                  swellAfternoonDecimal,

              periodMin: periodMin,
              periodMax: periodMax,

              onDirectionMorningChanged:
                  (value) {
                setState(() {
                  swellDirectionMorning =
                      value;
                });
              },

              onDirectionAfternoonChanged:
                  (value) {
                setState(() {
                  swellDirectionAfternoon =
                      value;
                });
              },

              onMorningHeightChanged:
                  (value) {
                setState(() {
                  swellMorningHeight =
                      value;
                });
              },

              onMorningDecimalChanged:
                  (value) {
                setState(() {
                  swellMorningDecimal =
                      value;
                });
              },

              onAfternoonHeightChanged:
                  (value) {
                setState(() {
                  swellAfternoonHeight =
                      value;
                });
              },

              onAfternoonDecimalChanged:
                  (value) {
                setState(() {
                  swellAfternoonDecimal =
                      value;
                });
              },

              onPeriodMinChanged: (value) {
                setState(() {
                  periodMin = value;
                });
              },

              onPeriodMaxChanged: (value) {
                setState(() {
                  periodMax = value;
                });
              },
              ),
),
          ),
        ],
      ),
    ),
  ),
),

                Transform.translate(
                  offset: const Offset(0, 12),

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

class _WaterTemperatureCard extends StatelessWidget {
  final int minValue;
  final int maxValue;
  final ValueChanged<int> onMinChanged;
  final ValueChanged<int> onMaxChanged;

  const _WaterTemperatureCard({
    required this.minValue,
    required this.maxValue,
    required this.onMinChanged,
    required this.onMaxChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = _waterColor(maxValue);

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color,
          width: 2,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.translate(
            offset: const Offset(0, 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.water_drop_rounded,
                  color: _waterColor(minValue),
                  size: 22,
                ),
                const SizedBox(width: 6),
                Text(
                  'EAU',
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 0),

          SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.translate(
                  offset: const Offset(0, -1),
                  child: const Text(
                    'De',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      height: 1.4,
                    ),
                  ),
                ),

                const SizedBox(width: 2),

                Transform.translate(
                  offset: const Offset(0, -17),
                  child: NumberPicker(
                    value: minValue,
                    minValue: 0,
                    maxValue: 35,
                    itemWidth: 30,
                    itemHeight: 28,
                    textStyle: const TextStyle(
                      fontSize: 9,
                      color: Colors.grey,
                    ),
                    selectedTextStyle: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: _waterColor(minValue),
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
                  offset: const Offset(0, -16),
                  child: NumberPicker(
                    value: maxValue,
                    minValue: 0,
                    maxValue: 35,
                    itemWidth: 30,
                    itemHeight: 28,
                    textStyle: const TextStyle(
                      fontSize: 9,
                      color: Colors.grey,
                    ),
                    selectedTextStyle: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: _waterColor(maxValue),
                    ),
                    onChanged: onMaxChanged,
                  ),
                ),

                const Text(
                  '°C',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    height: 1.4,
                    color: Colors.black,
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

class _SeaStateCard extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _SeaStateCard({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = _seaStateColor(value);

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color,
          width: 2,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    Icon(
      Icons.waves_rounded,
      color: color,
      size: 18,
    ),

    const SizedBox(width: 5),

    Text(
      'MER',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: 16,
        fontWeight: FontWeight.w900,
        height: 1.0,
      ),
    ),
  ],
),
          const SizedBox(height: 1),
          NumberPicker(
            value: value,
            minValue: 0,
            maxValue: seaStateLabels.length - 1,
            itemWidth: 120,
            itemHeight: 18,
            textMapper: (numberText) {
              final index = int.parse(numberText);
              return seaStateLabels[index];
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
        ],
      ),
    );
  }
}

class _TidesFullWidthCard extends StatelessWidget {
  final Color borderColor;

  final int highHour1;
  final int highMinute1;
  final int highHour2;
  final int highMinute2;
  final int highCoef;

  final int lowHour1;
  final int lowMinute1;
  final int lowHour2;
  final int lowMinute2;
  final int lowCoef;

  final ValueChanged<int> onHighHour1Changed;
  final ValueChanged<int> onHighMinute1Changed;
  final ValueChanged<int> onHighHour2Changed;
  final ValueChanged<int> onHighMinute2Changed;
  final ValueChanged<int> onHighCoefChanged;

  final ValueChanged<int> onLowHour1Changed;
  final ValueChanged<int> onLowMinute1Changed;
  final ValueChanged<int> onLowHour2Changed;
  final ValueChanged<int> onLowMinute2Changed;
  final ValueChanged<int> onLowCoefChanged;

  const _TidesFullWidthCard({
    required this.borderColor,
    required this.highHour1,
    required this.highMinute1,
    required this.highHour2,
    required this.highMinute2,
    required this.highCoef,
    required this.lowHour1,
    required this.lowMinute1,
    required this.lowHour2,
    required this.lowMinute2,
    required this.lowCoef,
    required this.onHighHour1Changed,
    required this.onHighMinute1Changed,
    required this.onHighHour2Changed,
    required this.onHighMinute2Changed,
    required this.onHighCoefChanged,
    required this.onLowHour1Changed,
    required this.onLowMinute1Changed,
    required this.onLowHour2Changed,
    required this.onLowMinute2Changed,
    required this.onLowCoefChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 120,
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: 3,
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 34,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'data/icons/tide_wave.png',
                  width: 26,
                  height: 26,
                  color: const Color(0xFF0277BD),
                ),
                const SizedBox(width: 8),
                const Text(
                  'MARÉES',
                  style: TextStyle(
                    color: Color(0xFF0277BD),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),

          _TideLine(
            isHigh: true,
            hour1: highHour1,
            minute1: highMinute1,
            hour2: highHour2,
            minute2: highMinute2,
            coef: highCoef,
            color: _tideColor(highCoef),
            onHour1Changed: onHighHour1Changed,
            onMinute1Changed: onHighMinute1Changed,
            onHour2Changed: onHighHour2Changed,
            onMinute2Changed: onHighMinute2Changed,
            onCoefChanged: onHighCoefChanged,
          ),

          Transform.translate(
  offset: const Offset(0, 6),

  child: _TideLine(
    isHigh: false,
    hour1: lowHour1,
            minute1: lowMinute1,
            hour2: lowHour2,
            minute2: lowMinute2,
            coef: lowCoef,
            color: _tideColor(lowCoef),
            onHour1Changed: onLowHour1Changed,
            onMinute1Changed: onLowMinute1Changed,
            onHour2Changed: onLowHour2Changed,
            onMinute2Changed: onLowMinute2Changed,
            onCoefChanged: onLowCoefChanged,
          ),
          ),
        ],
      ),
    );
  }
}

class _TideLine extends StatelessWidget {
  final bool isHigh;
  final int hour1;
  final int minute1;
  final int hour2;
  final int minute2;
  final int coef;
  final Color color;

  final ValueChanged<int> onHour1Changed;
  final ValueChanged<int> onMinute1Changed;
  final ValueChanged<int> onHour2Changed;
  final ValueChanged<int> onMinute2Changed;
  final ValueChanged<int> onCoefChanged;

  const _TideLine({
    required this.isHigh,
    required this.hour1,
    required this.minute1,
    required this.hour2,
    required this.minute2,
    required this.coef,
    required this.color,
    required this.onHour1Changed,
    required this.onMinute1Changed,
    required this.onHour2Changed,
    required this.onMinute2Changed,
    required this.onCoefChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 58,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Marées',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    Text(
                      isHigh ? 'Hautes' : 'Basses',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Text(
                  'à',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),

          _TidePicker(
            value: hour1,
            min: 0,
            max: 23,
            width: 24,
            color: color,
            onChanged: onHour1Changed,
          ),

          const SizedBox(width: 4),

const Text(
  'h',
  style: TextStyle(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w900,
  ),
),

const SizedBox(width: 4),

          _TidePicker(
            value: minute1,
            min: 0,
            max: 59,
            width: 24,
            color: color,
            onChanged: onMinute1Changed,
          ),

          const SizedBox(width: 4),
          const Text(
  'et',
  style: TextStyle(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w900,
  ),
),
          const SizedBox(width: 4),

          _TidePicker(
            value: hour2,
            min: 0,
            max: 23,
            width: 24,
            color: color,
            onChanged: onHour2Changed,
          ),

const SizedBox(width: 4),

const Text(
  'h',
  style: TextStyle(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w900,
  ),
),
          _TidePicker(
            value: minute2,
            min: 0,
            max: 59,
            width: 24,
            color: color,
            onChanged: onMinute2Changed,
          ),

          const SizedBox(width: 4),
          const Text(
  'Coef.',
  style: TextStyle(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w900,
  ),
),
          const SizedBox(width: 2),

          _TidePicker(
            value: coef,
            min: 20,
            max: 120,
            width: 34,
            color: color,
            onChanged: onCoefChanged,
          ),
        ],
      ),
    );
  }
}

class _TidePicker extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final double width;
  final Color color;
  final ValueChanged<int> onChanged;

  const _TidePicker({
    required this.value,
    required this.min,
    required this.max,
    required this.width,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 30,

      child: OverflowBox(
        minHeight: 60,
        maxHeight: 60,
        alignment: Alignment.topCenter,

        child: Transform.translate(
          offset: const Offset(0, -32),

          child: NumberPicker(
            value: value,
            minValue: min,
            maxValue: max,
            itemWidth: width,
            itemHeight: 30,

            textStyle: const TextStyle(
              fontSize: 9,
              height: 1.0,
              color: Colors.black38,
            ),

            selectedTextStyle: TextStyle(
              fontSize: 18,
              height: 1.0,
              fontWeight: FontWeight.w900,
              color: color,
            ),

            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _SwellFullWidthCard extends StatelessWidget {
  final Color borderColor;
  final String directionMorning;
  final String directionAfternoon;
  final int morningHeight;
  final int morningDecimal;
  final int afternoonHeight;
  final int afternoonDecimal;
  final int periodMin;
  final int periodMax;

  final ValueChanged<String> onDirectionMorningChanged;
  final ValueChanged<String> onDirectionAfternoonChanged;
  final ValueChanged<int> onMorningHeightChanged;
  final ValueChanged<int> onMorningDecimalChanged;
  final ValueChanged<int> onAfternoonHeightChanged;
  final ValueChanged<int> onAfternoonDecimalChanged;
  final ValueChanged<int> onPeriodMinChanged;
  final ValueChanged<int> onPeriodMaxChanged;

  const _SwellFullWidthCard({
    required this.borderColor,
    required this.directionMorning,
    required this.directionAfternoon,
    required this.morningHeight,
    required this.morningDecimal,
    required this.afternoonHeight,
    required this.afternoonDecimal,
    required this.periodMin,
    required this.periodMax,
    required this.onDirectionMorningChanged,
    required this.onDirectionAfternoonChanged,
    required this.onMorningHeightChanged,
    required this.onMorningDecimalChanged,
    required this.onAfternoonHeightChanged,
    required this.onAfternoonDecimalChanged,
    required this.onPeriodMinChanged,
    required this.onPeriodMaxChanged,
  });

  @override
  Widget build(BuildContext context) {
    final periodColor = _periodColor(periodMax);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: 3,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            top: -6,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'HOULE',
                style: TextStyle(
                  color: Color(0xFFC2185B),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),

          Positioned(
            top: 24,
            left: 0,
            right: 0,
            height: 130,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SwellCompassPicker(
                  label: 'Matin',
                  value: directionMorning,
                  height: morningHeight,
                  decimal: morningDecimal,
                  onChanged: onDirectionMorningChanged,
                  onHeightChanged: onMorningHeightChanged,
                  onDecimalChanged: onMorningDecimalChanged,
                ),
                const SizedBox(width: 4),
                _SwellCompassPicker(
                  label: 'Après-midi',
                  value: directionAfternoon,
                  height: afternoonHeight,
                  decimal: afternoonDecimal,
                  onChanged: onDirectionAfternoonChanged,
                  onHeightChanged: onAfternoonHeightChanged,
                  onDecimalChanged: onAfternoonDecimalChanged,
                ),
              ],
            ),
          ),

          Positioned(
            top: 150,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Période de',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                _SmallPicker(
                  value: periodMin,
                  min: 1,
                  max: 25,
                  color: periodColor,
                  width: 34,
                  onChanged: onPeriodMinChanged,
                ),
                const SizedBox(width: 4),
                const Text(
                  'à',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 4),
                _SmallPicker(
                  value: periodMax,
                  min: 1,
                  max: 25,
                  color: periodColor,
                  width: 34,
                  onChanged: onPeriodMaxChanged,
                ),
                const SizedBox(width: 6),
                const Text(
                  's',
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

class _SwellCompassPicker extends StatelessWidget {
  final String label;
  final String value;
  final int height;
  final int decimal;

  final ValueChanged<String> onChanged;
  final ValueChanged<int> onHeightChanged;
  final ValueChanged<int> onDecimalChanged;

  const _SwellCompassPicker({
    required this.label,
    required this.value,
    required this.height,
    required this.decimal,
    required this.onChanged,
    required this.onHeightChanged,
    required this.onDecimalChanged,
  });

  static const List<String> directions = [
    'N', 'NNE', 'NE', 'ENE',
    'E', 'ESE', 'SE', 'SSE',
    'S', 'SSO', 'SO', 'OSO',
    'O', 'ONO', 'NO', 'NNO',
  ];

  @override
  Widget build(BuildContext context) {
    final color = _swellColor(height * 10 + decimal);

    return Column(
      children: [
        Transform.translate(
          offset: const Offset(0, -10),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),

        SizedBox(
          width: 132,
          height: 108,

          child: Transform.translate(
            offset: const Offset(0, 6),

            child: Stack(
              alignment: Alignment.center,

              children: [
                Center(
                  child: Transform.translate(
                    offset: const Offset(0, -14),

                    child: SizedBox(
                      width: 88,
                      height: 54,

                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,

                        crossAxisAlignment:
                            CrossAxisAlignment.center,

                        children: [
                          SizedBox(
                            width: 24,
                            height: 54,

                            child: NumberPicker(
                              value: height,
                              minValue: 0,
                              maxValue: 25,

                              itemWidth: 30,
                              itemHeight: 28,

                              textStyle: const TextStyle(
                                fontSize: 11,
                                color: Colors.black38,
                              ),

                              selectedTextStyle: TextStyle(
                                fontSize: 17,
                                height: 1.0,
                                fontWeight: FontWeight.w900,
                                color: color,
                              ),

                              onChanged:
                                  onHeightChanged,
                            ),
                          ),

                          Transform.translate(
                            offset: const Offset(0, 14),

                            child: Text(
                              ',',

                              style: TextStyle(
                                color: color,
                                fontSize: 24,
                                height: 1.0,
                                fontWeight:
                                    FontWeight.w900,
                              ),
                            ),
                          ),

                          SizedBox(
                            width: 24,
                            height: 54,

                            child: NumberPicker(
                              value: decimal,
                              minValue: 0,
                              maxValue: 25,

                              itemWidth: 30,
                              itemHeight: 28,

                              textStyle: const TextStyle(
                                fontSize: 11,
                                color: Colors.black38,
                              ),

                              selectedTextStyle: TextStyle(
                                fontSize: 17,
                                height: 1.0,
                                fontWeight:
                                    FontWeight.w900,
                                color: color,
                              ),

                              onChanged:
                                  onDecimalChanged,
                            ),
                          ),

                          const SizedBox(width: 2),

                          Transform.translate(
                            offset: const Offset(0, 16),

                            child: const Text(
                              'm',

                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                height: 1.0,
                                fontWeight:
                                    FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                ...List.generate(
                  directions.length,
                  (index) {
                    final angle =
                        (index * 22.5 - 90) *
                            pi /
                            180;

                    final x = 52 * cos(angle);
                    final y = 52 * sin(angle);

                    final dir = directions[index];

                    final selected =
                        dir == value;

                    return Transform.translate(
                      offset: Offset(x, y),

                      child: GestureDetector(
                        onTap: () => onChanged(dir),

                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),

                          decoration: BoxDecoration(
                            color: selected
                                ? color
                                : Colors.transparent,

                            borderRadius:
                                BorderRadius.circular(8),

                            border: Border.all(
                              color: color,
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
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SmallPicker extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final double width;
  final Color color;
  final ValueChanged<int> onChanged;

  const _SmallPicker({
    required this.value,
    required this.min,
    required this.max,
    required this.width,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return NumberPicker(
      value: value,
      minValue: min,
      maxValue: max,
      itemWidth: width,
      itemHeight: 24,
      textStyle: const TextStyle(
        fontSize: 8,
        color: Colors.black38,
      ),
      selectedTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w900,
        color: color,
      ),
      onChanged: onChanged,
    );
  }
}

const TextStyle _smallTextStyle = TextStyle(
  color: Colors.black,
  fontSize: 10,
  fontWeight: FontWeight.w900,
);

const List<String> seaStateLabels = [
  'CALME',
  'RIDÉE',
  'BELLE',
  'PEU AGITÉE',
  'AGITÉE',
  'FORTE',
  'TRÈS FORTE',
  'GROSSE',
  'TRÈS GROSSE',
  'ÉNORME',
];

Color _seaStateColor(int value) {
  switch (value) {
    case 0:
      return const Color(0xFFEFEFEF);
    case 1:
      return const Color(0xFFD9D9D9);
    case 2:
      return const Color(0xFFCFCFCF);
    case 3:
      return const Color(0xFF6A00FF);
    case 4:
      return const Color(0xFF007BFF);
    case 5:
      return const Color(0xFF00B050);
    case 6:
      return const Color(0xFFFFB000);
    case 7:
      return const Color(0xFFFF3B00);
    case 8:
      return const Color(0xFFFF00FF);
    case 9:
      return const Color(0xFF4A4A4A);
    default:
      return const Color(0xFF007BFF);
  }
}

Color _waterColor(int value) {
  if (value <= 8) return const Color(0xFF0D47A1);
  if (value <= 12) return const Color(0xFF1565C0);
  if (value <= 16) return const Color(0xFF1E88E5);
  if (value <= 20) return const Color(0xFF26A69A);
  if (value <= 24) return const Color(0xFF43A047);
  if (value <= 28) return const Color(0xFFFB8C00);
  return const Color(0xFFE53935);
}

Color _tideColor(int value) {
  if (value <= 45) return const Color(0xFF26A69A);
  if (value <= 70) return const Color(0xFF1E88E5);
  if (value <= 95) return const Color(0xFF3949AB);
  return const Color(0xFF6A1B9A);
}

Color _swellColor(int valueInDecimeters) {
  if (valueInDecimeters <= 5) return const Color(0xFFF8BBD0);
  if (valueInDecimeters <= 10) return const Color(0xFFF06292);
  if (valueInDecimeters <= 20) return const Color(0xFFC2185B);
  if (valueInDecimeters <= 35) return const Color(0xFF8E24AA);
  if (valueInDecimeters <= 50) return const Color(0xFF6A1B9A);
  return const Color(0xFF4A148C);
}

Color _periodColor(int value) {
  if (value <= 6) return const Color(0xFFF06292);
  if (value <= 10) return const Color(0xFFC2185B);
  if (value <= 15) return const Color(0xFF8E24AA);
  return const Color(0xFF4A148C);
}

class _PeriodPicker extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final double width;
  final Color color;
  final ValueChanged<int> onChanged;

  const _PeriodPicker({
    required this.value,
    required this.min,
    required this.max,
    required this.width,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return NumberPicker(
      value: value,
      minValue: min,
      maxValue: max,
      itemWidth: width,
      itemHeight: 24,
      textStyle: const TextStyle(
        fontSize: 9,
        color: Colors.black38,
      ),
      selectedTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w900,
        color: color,
      ),
      onChanged: onChanged,
    );
  }
}