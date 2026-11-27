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

class Interactive3DCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? (isDark ? App3DTheme.cardDark : App3DTheme.cardLight),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
              offset: const Offset(0, 8),
              blurRadius: 16,
            ),
          ],
        ),
        child: child,
      ),
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

  @override
  Widget build(BuildContext context) {
    final rate = widget.rateController.usdToNewSyp;
    final ratio = widget.rateController.oldToNewSypRatio;
    return Stack(
      children: [
        if (_open)
          Positioned(
            right: 16,
            bottom: 90,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 260,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: App3DTheme.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: App3DTheme.accentCyan),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('حاسبة العملات 3D',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.close,
                              size: 18, color: Colors.white),
                          onPressed: () => setState(() => _open = false),
                        ),
                      ],
                    ),
                    Text('1\$ = ${rate.toStringAsFixed(2)} جديدة',
                        style: const TextStyle(color: App3DTheme.accentGold)),
                    Text('قديمة: ${(rate * ratio).toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white70)),
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
              width: 52,
              height: 52,
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
}
