import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PublicWebcamView extends StatefulWidget {
  final String url;

  const PublicWebcamView({super.key, required this.url});

  @override
  State<PublicWebcamView> createState() => _PublicWebcamViewState();
}

class _PublicWebcamViewState extends State<PublicWebcamView> {
  late final WebViewController _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();

    if (!kIsWeb) {
      _controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..setNavigationDelegate(
          NavigationDelegate(
            onWebResourceError: (_) {
              if (mounted) setState(() => _hasError = true);
            },
          ),
        );
    }

    final uri = _webcamUri(widget.url);
    if (uri == null) {
      _hasError = true;
    } else {
      _controller.loadRequest(uri);
    }
  }

  Uri? _webcamUri(String rawUrl) {
    var normalized = rawUrl.trim();
    if (normalized.isEmpty) return null;
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
    return Uri.tryParse(normalized);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'WEBCAM TEMPORAIREMENT INDISPONIBLE',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: WebViewWidget(controller: _controller),
    );
  }
}

class PublicWebcamFullScreenPage extends StatelessWidget {
  final String url;

  const PublicWebcamFullScreenPage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'WEBCAM EN DIRECT',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: PublicWebcamView(url: url),
        ),
      ),
    );
  }
}
