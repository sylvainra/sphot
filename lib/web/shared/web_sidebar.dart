import 'package:flutter/material.dart';

import 'web_colors.dart';
import 'web_menu_item.dart';

class WebSidebar extends StatelessWidget {
  final String title;
  final List<WebMenuItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const WebSidebar({
    super.key,
    required this.title,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: WebColors.sidebar,
      child: Column(
        children: [
          Container(
            height: 72,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white24),
              ),
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: WebColors.red,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = index == selectedIndex;

                return Material(
  color: WebColors.sidebar,
  child: InkWell(
    onTap: () => onSelected(index),
    hoverColor: Colors.transparent,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),
      child: Row(
        children: [
          Icon(
            item.icon,
            color: selected
                ? WebColors.red
                : WebColors.textMuted,
          ),
          const SizedBox(width: 16),
          Text(
            item.title,
            style: TextStyle(
              color: selected
                  ? WebColors.red
                  : WebColors.textLight,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  ),
);
              },
            ),
          ),
        ],
      ),
    );
  }
}