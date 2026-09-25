import 'package:flutter/material.dart';

class SauveteurDropdownOption {
  final String value;
  final String label;

  const SauveteurDropdownOption({
    required this.value,
    required this.label,
  });
}

/// Menu déroulant SPHOT SAUVETEUR harmonisé avec les filtres Super Admin.
class SauveteurStyledDropdown extends StatefulWidget {
  static const Color borderColor = Color(0xFF1E3A8A);
  static const Color selectedColor = Color(0xFFDC2626);

  final String labelText;
  final String? value;
  final List<SauveteurDropdownOption> options;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final double maxMenuHeight;

  const SauveteurStyledDropdown({
    super.key,
    required this.labelText,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.maxMenuHeight = 245,
  });

  @override
  State<SauveteurStyledDropdown> createState() =>
      _SauveteurStyledDropdownState();
}

class _SauveteurStyledDropdownState extends State<SauveteurStyledDropdown> {
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _overlay;

  String get _displayText {
    final selected = widget.options.where(
      (option) => option.value == widget.value,
    );

    if (selected.isNotEmpty) {
      return selected.first.label;
    }

    return widget.options.isEmpty
        ? 'Aucun choix disponible'
        : 'Sélectionner';
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _toggleOverlay() {
    if (!widget.enabled || widget.options.isEmpty) return;

    if (_overlay != null) {
      _removeOverlay();
      return;
    }

    final context = _fieldKey.currentContext;
    if (context == null) return;

    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final scrollController = ScrollController();

    _overlay = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            Positioned(
              left: position.dx,
              top: position.dy + size.height - 12,
              width: size.width,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: widget.maxMenuHeight,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: const Border(
                      left: BorderSide(
                        color: SauveteurStyledDropdown.borderColor,
                        width: 1.4,
                      ),
                      right: BorderSide(
                        color: SauveteurStyledDropdown.borderColor,
                        width: 1.4,
                      ),
                      bottom: BorderSide(
                        color: SauveteurStyledDropdown.borderColor,
                        width: 1.4,
                      ),
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ScrollbarTheme(
                    data: const ScrollbarThemeData(
                      thumbColor: WidgetStatePropertyAll(
                        SauveteurStyledDropdown.borderColor,
                      ),
                      trackVisibility: WidgetStatePropertyAll(false),
                    ),
                    child: Scrollbar(
                      controller: scrollController,
                      thumbVisibility: widget.options.length > 5,
                      thickness: 8,
                      radius: const Radius.circular(10),
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: widget.options.map((option) {
                          final selected = option.value == widget.value;

                          return InkWell(
                            onTap: () {
                              widget.onChanged(option.value);
                              _removeOverlay();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    color: selected
                                        ? SauveteurStyledDropdown.selectedColor
                                        : SauveteurStyledDropdown.borderColor,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      option.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: selected
                                            ? SauveteurStyledDropdown
                                                .selectedColor
                                            : SauveteurStyledDropdown
                                                .borderColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlay!);
  }

  @override
  Widget build(BuildContext context) {
    final muted = !widget.enabled || widget.options.isEmpty;

    return GestureDetector(
      key: _fieldKey,
      onTap: _toggleOverlay,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.labelText,
          labelStyle: TextStyle(
            color: muted
                ? Colors.black38
                : SauveteurStyledDropdown.borderColor,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: SauveteurStyledDropdown.borderColor,
              width: 1.6,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: muted
                  ? Colors.black26
                  : SauveteurStyledDropdown.borderColor,
              width: 1.6,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _displayText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: muted
                      ? Colors.black38
                      : SauveteurStyledDropdown.selectedColor,
                ),
              ),
            ),
            Icon(
              Icons.checklist_rounded,
              color: muted
                  ? Colors.black26
                  : SauveteurStyledDropdown.selectedColor,
              size: 22,
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: muted
                  ? Colors.black26
                  : SauveteurStyledDropdown.selectedColor,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}
