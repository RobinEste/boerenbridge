import 'package:flutter/material.dart';

/// App logo widget - shows the Boeren Bridge logo
class AppLogo extends StatelessWidget {
  final double height;

  const AppLogo({
    super.key,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      height: height,
      fit: BoxFit.contain,
    );
  }
}
