import 'package:flutter/material.dart';

class Responsive {
  const Responsive._();

  static bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

  static bool isMedium(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 600 && width < 1000;
  }

  static bool isExpanded(BuildContext context) => MediaQuery.sizeOf(context).width >= 1000;

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1400) {
      return 28;
    }
    if (width >= 1000) {
      return 24;
    }
    if (width >= 700) {
      return 20;
    }
    return 14;
  }

  static double maxContentWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1400) {
      return 1320;
    }
    if (width >= 1000) {
      return 1060;
    }
    return width;
  }
}

class ResponsiveContainer extends StatelessWidget {
  const ResponsiveContainer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Responsive.maxContentWidth(context)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
          child: child,
        ),
      ),
    );
  }
}
