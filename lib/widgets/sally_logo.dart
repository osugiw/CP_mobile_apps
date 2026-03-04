import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SallyLogo extends StatelessWidget {
  final double width;
  final double height;

  const SallyLogo({
    super.key,
    this.width = 100,
    this.height = 100,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/sally_logo.svg',
      width: width,
      height: height,
    );
  }
}
