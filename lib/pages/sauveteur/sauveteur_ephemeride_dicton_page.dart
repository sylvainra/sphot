import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SauveteurEphemerideDictonPage extends StatefulWidget {
  final Color profileColor;

  const SauveteurEphemerideDictonPage({
    super.key,
    required this.profileColor,
  });

  @override
State<SauveteurEphemerideDictonPage> createState() =>
    _SauveteurEphemerideDictonPageState();
}

class _SauveteurEphemerideDictonPageState
    extends State<SauveteurEphemerideDictonPage> {
  late stt.SpeechToText _speech;

  bool _isListening = false;
  int? _listeningZone;

  final TextEditingController ephemerideController =
      TextEditingController();

  final TextEditingController dictonController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  @override
  void dispose() {
    ephemerideController.dispose();
    dictonController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _listenToZone(
    int zone,
    TextEditingController controller,
  ) async {
    if (_isListening && _listeningZone == zone) {
      setState(() {
        _isListening = false;
        _listeningZone = null;
      });

      await _speech.stop();
      return;
    }

    final bool available = await _speech.initialize();

    if (!available) return;

    setState(() {
      _isListening = true;
      _listeningZone = zone;
    });

    _speech.listen(
      localeId: 'fr_FR',
      onResult: (result) {
        setState(() {
          controller.text = result.recognizedWords;
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: controller.text.length),
          );
        });
      },
    );
  }

  Widget _textZone({
    required String hint,
    required int zone,
    required TextEditingController controller,
  }) {
    final bool listening = _isListening && _listeningZone == zone;

    return Container(
      width: double.infinity,
      height: 194,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.black,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 20,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => _listenToZone(zone, controller),
              child: Icon(
                listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: listening ? Colors.red : widget.profileColor,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required String hint,
    required int zone,
    required TextEditingController controller,
  }) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFF9A825),
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        _textZone(
          hint: hint,
          zone: zone,
          controller: controller,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
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

                  Text(
                    'ÉPHÉMÉRIDE DICTON',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: widget.profileColor,
                      letterSpacing: 0.6,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.black,
                          width: 2,
                        ),
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            _section(
                              title: 'ÉPHÉMÉRIDE',
                              hint: 'Dictez ou saisissez ici l’éphéméride du jour...',
                              zone: 0,
                              controller: ephemerideController,
                            ),

                            const SizedBox(height: 10),

                            _section(
                              title: 'DICTON',
                              hint: 'Dictez ou saisissez ici le dicton du jour...',
                              zone: 1,
                              controller: dictonController,
                            ),

                            const SizedBox(height: 60),
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