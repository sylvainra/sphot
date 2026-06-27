import 'package:flutter/material.dart';

import 'web_menu_item.dart';
import 'web_sidebar.dart';

import 'web_colors.dart';

import 'web_top_bar.dart';

class WebLayout extends StatefulWidget {
  final String title;
  final List<WebMenuItem> menuItems;

  const WebLayout({
    super.key,
    required this.title,
    required this.menuItems,
  });

  @override
  State<WebLayout> createState() => _WebLayoutState();
}

class _WebLayoutState extends State<WebLayout> {
  int selectedIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
  children: [
    if (selectedIndex != 1)
      WebSidebar(
        title: widget.title,
        items: widget.menuItems,
        selectedIndex: selectedIndex,
        onSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
      ),

    Expanded(
      child: Container(
        color: WebColors.background,
        child: Column(
          children: [
            if (selectedIndex != 1)
              const WebTopBar(),

            Expanded(
              child: widget.menuItems[selectedIndex].page,
            ),
          ],
        ),
      ),
    ),
  ],
)
    );
  }
}