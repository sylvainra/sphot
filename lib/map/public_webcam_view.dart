import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PublicWebcamView extends StatefulWidget {
  final String url;
  final bool forceImage;

  const PublicWebcamView({
    super.key,
    required this.url,
    this.forceImage = false,
  });

  @override
  State<PublicWebcamView> createState() => _PublicWebcamViewState();
}

class _PublicWebcamViewState extends State<PublicWebcamView> {
  late final WebViewController _controller;
  bool _hasError = false;
  late final bool _isDirectImage;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    _isDirectImage = widget.forceImage || _looksLikeImage(widget.url);

    if (!_isDirectImage && !kIsWeb) {
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

    if (!_isDirectImage) {
      final uri = _webcamUri(widget.url);
      if (uri == null) {
        _hasError = true;
      } else {
        _controller.loadRequest(uri);
      }
    }
  }

  bool _looksLikeImage(String rawUrl) {
    final normalized = Uri.decodeFull(rawUrl).toLowerCase();

    return RegExp(
      r'\.(jpg|jpeg|png|webp|gif)(?:$|[?&#])',
    ).hasMatch(normalized);
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
    if (_isDirectImage) {
      return ColoredBox(
        color: Colors.black,
        child: Image.network(
          widget.url,
          fit: BoxFit.cover,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          errorBuilder: (_, __, ___) => const Center(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'PHOTO TEMPORAIREMENT INDISPONIBLE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
    }

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

// Cette galerie n'est construite que dans la fiche d'un SPHOT sélectionné.
class PublicSphotPhotoGallery extends StatefulWidget {
  const PublicSphotPhotoGallery({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<PublicSphotPhotoGallery> createState() =>
      _PublicSphotPhotoGalleryState();
}

class _PublicSphotPhotoGalleryState extends State<PublicSphotPhotoGallery> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex
        .clamp(0, widget.urls.isEmpty ? 0 : widget.urls.length - 1)
        .toInt();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void didUpdateWidget(covariant PublicSphotPhotoGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.join('|') != widget.urls.join('|')) {
      _currentIndex = 0;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showPage(int index) {
    if (index < 0 || index >= widget.urls.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return const Center(
        child: Text('PHOTO TEMPORAIREMENT INDISPONIBLE'),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
            controller: _pageController,
            itemCount: widget.urls.length,
            onPageChanged: (index) => setState(() {
              _currentIndex = index;
            }),
            itemBuilder: (_, index) => PublicWebcamView(
              url: widget.urls[index],
              forceImage: true,
            ),
          ),
        ),
        if (widget.urls.length > 1)
          SizedBox(
            height: 38,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Photo précédente',
                  onPressed: _currentIndex > 0
                      ? () => _showPage(_currentIndex - 1) : null,
                  icon: const Icon(Icons.chevron_left,
                    color: Colors.white),
                ),
                Text(
                  (_currentIndex + 1).toString() +
                      ' / ' + widget.urls.length.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800, color: Colors.white,
                  ),
                ),
                IconButton(
                  tooltip: 'Photo suivante',
                  onPressed: _currentIndex < widget.urls.length - 1
                      ? () => _showPage(_currentIndex + 1) : null,
                  icon: const Icon(Icons.chevron_right,
                    color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PublicWebcamFullScreenPage extends StatelessWidget {
  final String url;
  final bool forceImage;
  final List<String> photoUrls;

  const PublicWebcamFullScreenPage({
    super.key,
    required this.url,
    this.forceImage = false,
    this.photoUrls = const <String>[],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          forceImage ? 'PHOTO DU SPHOT' : 'WEBCAM EN DIRECT',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: forceImage && photoUrls.length > 1
              ? PublicSphotPhotoGallery(urls: photoUrls)
              : PublicWebcamView(url: url, forceImage: forceImage),
        ),
      ),
    );
  }
}
