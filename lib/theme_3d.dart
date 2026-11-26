import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:chad_avs_pos_3d/database.dart';

// ============================================================================
// 1. 3D THEME & INTERACTIVE CARDS (CHAD A.V.S EDITION)
// ============================================================================

class App3DTheme {
  static const Color darkBg = Color(0xFF0A121E);
  static const Color navyHeader = Color(0xFF0F2942);
  static const Color cardDark = Color(0xFF132236);
  static const Color lightBg = Color(0xFFF1F5F9);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color accentGold = Color(0xFFE59A24);
  static const Color accentCyan = Color(0xFF18B6D8);
  static const Color successGreen = Color(0xFF16A34A);
  static const Color dangerRed = Color(0xFFDC2626);

  static ThemeData buildTheme({required bool isDark}) {
    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: isDark ? darkBg : lightBg,
      primaryColor: navyHeader,
      colorScheme: isDark
          ? const ColorScheme.dark(
              primary: accentCyan,
              secondary: accentGold,
              surface: cardDark,
              error: dangerRed,
            )
          : const ColorScheme.light(
              primary: navyHeader,
              secondary: accentGold,
              surface: cardLight,
              error: dangerRed,
            ),
      useMaterial3: true,
    );
  }
}

class Interactive3DCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double borderRadius;

  const Interactive3DCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.borderRadius = 18,
  });

  @override
  State<Interactive3DCard> createState() => _Interactive3DCardState();
}

class _Interactive3DCardState extends State<Interactive3DCard> {
  double _tiltX = 0;
  double _tiltY = 0;
  bool _pressed = false;

  void _updateTilt(Offset localPos, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final dx = (localPos.dx / size.width) - 0.5;
    final dy = (localPos.dy / size.height) - 0.5;
    setState(() {
      _tiltY = dx * 0.14;
      _tiltX = -dy * 0.14;
    });
  }

  void _resetTilt() {
    setState(() {
      _tiltX = 0;
      _tiltY = 0;
      _pressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        widget.color ?? (isDark ? App3DTheme.cardDark : App3DTheme.cardLight);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 300,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 120,
        );

        return GestureDetector(
          onTap: widget.onTap,
          onTapDown: (d) {
            setState(() => _pressed = true);
            _updateTilt(d.localPosition, size);
          },
          onPanUpdate: (d) => _updateTilt(d.localPosition, size),
          onPanEnd: (_) => _resetTilt(),
          onTapUp: (_) => _resetTilt(),
          onTapCancel: _resetTilt,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(_tiltX)
              ..rotateY(_tiltY)
              ..scale(_pressed ? 0.985 : 1.0),
            transformAlignment: Alignment.center,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.07),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
                  offset: Offset(0, _pressed ? 3 : 8),
                  blurRadius: _pressed ? 8 : 16,
                ),
                BoxShadow(
                  color: App3DTheme.accentCyan.withValues(alpha: 0.06),
                  offset: const Offset(0, -2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

// ============================================================================
// 2. FLOATING 3D CALCULATOR OVERLAY (CHAD A.V.S)
// ============================================================================

class Floating3DCalculatorOverlay extends StatefulWidget {
  final ExchangeRateController rateController;

  const Floating3DCalculatorOverlay({
    super.key,
    required this.rateController,
  });

  @override
  State<Floating3DCalculatorOverlay> createState() =>
      _Floating3DCalculatorOverlayState();
}

class _Floating3DCalculatorOverlayState
    extends State<Floating3DCalculatorOverlay> {
  Offset _fabOffset = const Offset(20, 120);
  bool _isOpen = false;
  String _expression = '';
  String _result = '0';
  int _tabIndex = 0; // 0: calc | 1: currency | 2: units

  final _unitInputCtrl = TextEditingController(text: '1');
  String _unitCategory = 'الطول (متر <-> سم)';

  @override
  void dispose() {
    _unitInputCtrl.dispose();
    super.dispose();
  }

  void _pressKey(String key) {
    setState(() {
      if (key == 'C') {
        _expression = '';
        _result = '0';
        return;
      }
      if (key == '⌫') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
        return;
      }
      if (key == '=') {
        _result = _evaluateSimple(_expression);
        return;
      }
      _expression += key;
    });
  }

  String _evaluateSimple(String expr) {
    final cleaned = expr.replaceAll('×', '*').replaceAll('÷', '/').trim();
    if (cleaned.isEmpty) return '0';
    final tokens = RegExp(r'(\d+\.?\d*|[+\-*/])')
        .allMatches(cleaned)
        .map((m) => m.group(0)!)
        .toList();
    if (tokens.isEmpty) return '0';

    double? acc = double.tryParse(tokens.first);
    if (acc == null) return _expression;

    String? op;
    for (int i = 1; i < tokens.length; i++) {
      final t = tokens[i];
      if (t == '+' || t == '-' || t == '*' || t == '/') {
        op = t;
      } else {
        final numVal = double.tryParse(t);
        if (numVal != null && op != null) {
          if (op == '+') acc = acc! + numVal;
          if (op == '-') acc = acc! - numVal;
          if (op == '*') acc = acc! * numVal;
          if (op == '/') acc = numVal == 0 ? 0 : acc! / numVal;
        }
      }
    }
    return acc!.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }

  String _convertUnit() {
    final val = double.tryParse(_unitInputCtrl.text.trim()) ?? 0;
    if (_unitCategory.contains('الطول')) {
      return '${(val * 100).toStringAsFixed(2)} سم';
    }
    if (_unitCategory.contains('الوزن')) {
      return '${(val * 1000).toStringAsFixed(2)} غرام';
    }
    return '${(val * 1000).toStringAsFixed(2)} مل';
  }

  @override
  Widget build(BuildContext context) {
    final rate = widget.rateController.usdToNewSyp;
    final ratio = widget.rateController.oldToNewSypRatio;
    final numericVal = double.tryParse(_result) ??
        double.tryParse(_expression) ??
        1.0;

    return Stack(
      children: [
        if (_isOpen)
          Positioned(
            right: 16,
            bottom: 90,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 310,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: App3DTheme.cardDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: App3DTheme.accentCyan.withValues(alpha: 0.4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'حاسبة CHAD A.V.S 3D',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: Colors.white),
                          onPressed: () => setState(() => _isOpen = false),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _modeChip('حاسبة', 0),
                        const SizedBox(width: 6),
                        _modeChip('عملات', 1),
                        const SizedBox(width: 6),
                        _modeChip('وحدات', 2),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_tabIndex == 0) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: App3DTheme.darkBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _expression.isEmpty ? '0' : _expression,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white60,
                              ),
                            ),
                            Text(
                              _result,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: App3DTheme.accentGold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...const [
                        ['C', '⌫', '÷', '×'],
                        ['7', '8', '9', '-'],
                        ['4', '5', '6', '+'],
                        ['1', '2', '3', '='],
                        ['0', '.', '10%', '20%'],
                      ].map(
                        (row) => Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: row
                                .map(
                                  (k) => Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      child: GestureDetector(
                                        onTap: () => _pressKey(k),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 9),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: App3DTheme.navyHeader,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            k,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ] else if (_tabIndex == 1) ...[
                      Text(
                        'القيمة الأساسية: ${numericVal.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'بالدولار: \$${numericVal.toStringAsFixed(2)}',
                        style: const TextStyle(color: App3DTheme.accentCyan),
                      ),
                      Text(
                        'ليرة جديدة: ${(numericVal * rate).toStringAsFixed(1)}',
                        style: const TextStyle(color: App3DTheme.accentGold),
                      ),
                      Text(
                        'ليرة قديمة: ${(numericVal * rate * ratio).toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ] else ...[
                      DropdownButton<String>(
                        value: _unitCategory,
                        isExpanded: true,
                        dropdownColor: App3DTheme.cardDark,
                        style: const TextStyle(color: Colors.white),
                        items: const [
                          DropdownMenuItem(
                            value: 'الطول (متر <-> سم)',
                            child: Text('الطول (متر <-> سم)'),
                          ),
                          DropdownMenuItem(
                            value: 'الوزن (كغ <-> غ)',
                            child: Text('الوزن (كغ <-> غ)'),
                          ),
                          DropdownMenuItem(
                            value: 'الحجم (لتر <-> مل)',
                            child: Text('الحجم (لتر <-> مل)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _unitCategory = v);
                        },
                      ),
                      TextField(
                        controller: _unitInputCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'الناتج: ${_convertUnit()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: App3DTheme.accentGold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          left: _fabOffset.dx,
          top: _fabOffset.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              final size = MediaQuery.of(context).size;
              setState(() {
                _fabOffset = Offset(
                  (_fabOffset.dx + details.delta.dx)
                      .clamp(8.0, math.max(8.0, size.width - 68)),
                  (_fabOffset.dy + details.delta.dy)
                      .clamp(60.0, math.max(60.0, size.height - 120)),
                );
              });
            },
            onTap: () => setState(() => _isOpen = !_isOpen),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [App3DTheme.accentGold, Color(0xFFC27803)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: App3DTheme.accentGold.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.calculate_rounded,
                color: Colors.black,
                size: 28,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeChip(String title, int idx) {
    final active = _tabIndex == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? App3DTheme.accentCyan : App3DTheme.darkBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: active ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
```[span_0](start_span)[span_0](end_span)

---

