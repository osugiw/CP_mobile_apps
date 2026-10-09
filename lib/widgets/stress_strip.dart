import 'package:flutter/material.dart';
import '../models/stress_reading.dart';

/// Tiny bar strip showing how stress changed during one conversation.
/// Each bar is one sample; taller and warmer means more tension.
class StressStrip extends StatelessWidget {
  final List<int> values; // 0 to 100
  final double height;

  const StressStrip({super.key, required this.values, this.height = 28});

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return SizedBox(height: height);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                height: 4 + (height - 4) * v.clamp(0, 100) / 100,
                decoration: BoxDecoration(
                  color: StressLevel.fromScore(v).color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
