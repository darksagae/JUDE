import 'package:flutter/material.dart';

/// Shared breakpoints and layout helpers for phone / tablet / desktop.
class Responsive {
  static const double phone = 600;
  static const double tablet = 760;
  static const double desktop = 900;

  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < phone;

  static bool isNarrow(double width) => width < phone;

  static EdgeInsets pagePadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return EdgeInsets.all(w < phone ? 12 : 20);
  }

  /// Dialog content width that fits narrow screens.
  static double dialogWidth(BuildContext context, {double max = 460}) {
    final w = MediaQuery.sizeOf(context).width;
    final cap = w < phone ? w * 0.92 : max;
    return cap.clamp(280.0, max);
  }
}

/// Title row that stacks the action button below on narrow widths.
class ResponsiveHeader extends StatelessWidget {
  final String title;
  final TextStyle? titleStyle;
  final Widget action;
  final double stackBelow;

  const ResponsiveHeader({
    super.key,
    required this.title,
    required this.action,
    this.titleStyle,
    this.stackBelow = 520,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final style = titleStyle ??
          const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1E293B));
      if (c.maxWidth < stackBelow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: style),
            const SizedBox(height: 10),
            action,
          ],
        );
      }
      return Row(children: [
        Expanded(child: Text(title, style: style)),
        action,
      ]);
    });
  }
}
