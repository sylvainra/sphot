import 'package:flutter/material.dart';

import '../services/web_proconnect_auth_service.dart';

class WebAdminRedirectGate extends StatefulWidget {
  final Widget child;

  const WebAdminRedirectGate({
    super.key,
    required this.child,
  });

  @override
  State<WebAdminRedirectGate> createState() => _WebAdminRedirectGateState();
}

class _WebAdminRedirectGateState extends State<WebAdminRedirectGate> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkRedirectResult();
  }

  Future<void> _checkRedirectResult() async {
    print('Redirect gate désactivé pour test popup');

    if (!mounted) return;

    setState(() {
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return widget.child;
  }
}