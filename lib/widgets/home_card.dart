import 'package:flutter/material.dart';

class HomeCard extends StatelessWidget {
  final String title;
  final double? height;
  final double? width;

  const HomeCard({
    super.key,
    required this.title,
    this.height,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    const Color cardBlue = Color(0xFFAEC0DF);

    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: cardBlue,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Center(
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
