import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:chad_avs_pos_3d/database.dart';

class App3DTheme {
  static const darkBg = Color(0xFF0A121E);
  static const navyHeader = Color(0xFF0F2942);
  static const cardDark = Color(0xFF132236);
  static const lightBg = Color(0xFFF1F5F9);
  static const cardLight = Color(0xFFFFFFFF);
  static const accentGold = Color(0xFFE59A24);
  static const accentCyan = Color(0xFF18B6D8);
  static const successGreen = Color(0xFF16A34A);
  static const dangerRed = Color(0xFFDC2626);

  static ThemeData buildTheme({required bool isDark}) => ThemeData(
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
  double _rx = 0, _ry = 0;
  bool _down = false;

  void _tilt(Offset pos, Size s) {
    if (s.width <= 0 || s.height <= 0) return;
    setState(() {
      _ry = ((pos.dx / s.width) - 0.5) * 0.14;
      _rx = -((pos.dy / s.height) - 0.5) * 0.14;
    });
  }

  void _reset() => setState(() => _rx = _ry = _down = false);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, c) {
        final s = Size(
          c.maxWidth.isFinite ? c.maxWidth : 300,
          c.maxHeight.isFinite ? c.maxHeight : 120,
        );
        return GestureDetector(
          onTap: widget.onTap,
          onTapDown: (d) {
            setState(() => _down = true);
            _tilt(d.localPosition, s);
          },
          onPanUpdate: (d) => _tilt(d.localPosition, s),
          onPanEnd: (_) => _reset(),
          onTapUp: (_) => _reset(),
          onTapCancel: _reset,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(_rx)
              ..rotateY(_ry)
              ..scale(_down ? 0.985 : 1.0),
            transformAlignment: Alignment.center,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: widget.color ??
                  (isDark ? App3DTheme.cardDark : App3DTheme.cardLight),
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
                  offset: Offset(0, _down ? 3 : 8),
                  blurRadius: _down ? 8 : 16,
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

class Floating3DCalculatorOverlay extends StatefulWidget {
  final ExchangeRateController rateController;
  const Floating3DCalculatorOverlay({super.key, required this.rateController});

  @override
  State<Floating3DCalculatorOverlay> createState() =>
      _Floating3DCalculatorOverlayState();
}

class _Floating3DCalculatorOverlayState
    extends State<Floating3DCalculatorOverlay> {
  Offset _pos = const Offset(20, 120);
  bool _open = false;
  String _expr = '', _res = '0';
  int _tab = 0;
  final _unitCtrl = TextEditingController(text: '1');
  String _unitType = 'len';

  @override
  void dispose() {
    _unitCtrl.dispose();
    super.dispose();
  }

  void _key(String k) {
    setState(() {
      if (k == 'C') {
        _expr = '';
        _res = '0';
      } else if (k == '⌫') {
        if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
      } else if (k == '=') {
        _res = _calc(_expr);
      } else {
        _expr += k;
      }
    });
  }

  String _calc(String s) {
    final clean = s.replaceAll('×', '*').replaceAll('÷', '/');
    final parts = RegExp(r'(\d+\.?\d*|[+\-*/])')
        .allMatches(clean)
        .map((m) => m.group(0)!)
        .toList();
    if (parts.isEmpty) return '0';
    double? acc = double.tryParse(parts.first);
    if (acc == null) return _expr;
    String? op;
    for (int i = 1; i < parts.length; i++) {
      final t = parts[i];
      if ('+-*/'.contains(t)) {
        op = t;
      } else {
        final v = double.tryParse(t);
        if (v != null && op != null) {
          if (op == '+') acc = acc! + v;
          if (op == '-') acc = acc! - v;
          if (op == '*') acc = acc! * v;
          if (op == '/') acc = v == 0 ? 0 : acc! / v;
        }
      }
    }
    return acc!.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }

  String _unitOut() {
    final v = double.tryParse(_unitCtrl.text.trim()) ?? 0;
    return _unitType == 'len'
        ? '${(v * 100).toStringAsFixed(2)} سم'
        : '${(v * 1000).toStringAsFixed(2)} غ / مل';
  }

  @override
  Widget build(BuildContext context) {
    final rate = widget.rateController.usdToNewSyp;
    final ratio = widget.rateController.oldToNewSypRatio;
    final val = double.tryParse(_res) ?? double.tryParse(_expr) ?? 1.0;

    return Stack(
      children: [
        if (_open)
          Positioned(
            right: 16,
            bottom: 90,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 300,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: App3DTheme.cardDark,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: App3DTheme.accentCyan),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('حاسبة CHAD A.V.S 3D',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        IconButton(
                          icon: const Icon(Icons.close,
                              size: 18, color: Colors.white),
                          onPressed: () => setState(() => _open = false),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _chip('حاسبة', 0),
                        const SizedBox(width: 6),
                        _chip('عملات', 1),
                        const SizedBox(width: 6),
                        _chip('وحدات', 2),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_tab == 0) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: App3DTheme.darkBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_expr.isEmpty ? '0' : _expr,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white60)),
                            Text(_res,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: App3DTheme.accentGold)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...const [
                        ['C', '⌫', '÷', '×'],
                        ['7', '8', '9', '-'],
                        ['4', '5', '6', '+'],
                        ['1', '2', '3', '='],
                      ].map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: r
                                .map((k) => Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 2),
                                        child: GestureDetector(
                                          onTap: () => _key(k),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: App3DTheme.navyHeader,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(k,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                    ] else if (_tab == 1) ...[
                      Text('دولار: \$${val.toStringAsFixed(2)}',
                          style: const TextStyle(color: App3DTheme.accentCyan)),
                      Text('جديدة: ${(val * rate).toStringAsFixed(1)}',
                          style: const TextStyle(color: App3DTheme.accentGold)),
                      Text(
                          'قديمة: ${(val * rate * ratio).toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white70)),
                    ] else ...[
                      DropdownButton<String>(
                        value: _unitType,
                        isExpanded: true,
                        dropdownColor: App3DTheme.cardDark,
                        style: const TextStyle(color: Colors.white),
                        items: const [
                          DropdownMenuItem(
                              value: 'len', child: Text('متر -> سم')),
                          DropdownMenuItem(
                              value: 'mass', child: Text('كغ/لتر -> غ/مل')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _unitType = v);
                        },
                      ),
                      TextField(
                        controller: _unitCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 6),
                      Text(_unitOut(),
                          style: const TextStyle(
                              color: App3DTheme.accentGold,
                              fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          left: _pos.dx,
          top: _pos.dy,
          child: GestureDetector(
            onPanUpdate: (d) {
              final s = MediaQuery.of(context).size;
              setState(() {
                _pos = Offset(
                  (_pos.dx + d.delta.dx)
                      .clamp(8.0, math.max(8.0, s.width - 68)),
                  (_pos.dy + d.delta.dy)
                      .clamp(60.0, math.max(60.0, s.height - 120)),
                );
              });
            },
            onTap: () => setState(() => _open = !_open),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: App3DTheme.accentGold,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.calculate_rounded, color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, int i) {
    final active = _tab == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? App3DTheme.accentCyan : App3DTheme.darkBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.black : Colors.white)),
        ),
      ),
    );
  }
}
st TextStyle(
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


