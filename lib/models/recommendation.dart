import 'package:flutter/material.dart';
import 'stress_reading.dart';

/// What happens when the user taps a recommendation's button.
enum RecommendationAction { none, breathing }

class Recommendation {
  final String title;
  final String description;
  final IconData icon;
  final int minutes;
  final RecommendationAction action;

  const Recommendation({
    required this.title,
    required this.description,
    required this.icon,
    required this.minutes,
    this.action = RecommendationAction.none,
  });
}

/// Short message shown in the banner at the top of the recommendation page.
const Map<StressLevel, String> levelMessages = {
  StressLevel.calm:
      "Your voice sounds relaxed. Keep doing what you're doing, small habits help keep it this way.",
  StressLevel.elevated:
      'Your voice shows some signs of tension. A short pause can help you reset.',
  StressLevel.high:
      'Your voice shows strong signs of stress. Take a moment for yourself, you do not have to handle this alone.',
};

/// Dummy content for the mockup. Later this can come from the server too.
const Map<StressLevel, List<Recommendation>> recommendationsByLevel = {
  StressLevel.calm: [
    Recommendation(
      title: 'Take a gentle walk',
      description: 'A short, easy walk or light stretch keeps your energy steady.',
      icon: Icons.directions_walk,
      minutes: 10,
    ),
    Recommendation(
      title: 'Stay hydrated',
      description: 'Have a glass of water. Small habits add up through the day.',
      icon: Icons.water_drop_outlined,
      minutes: 1,
    ),
    Recommendation(
      title: 'Note one good thing',
      description: 'Write down one thing that went well today.',
      icon: Icons.edit_note,
      minutes: 3,
    ),
    Recommendation(
      title: 'Plan a restful night',
      description: 'Try to keep a regular bedtime tonight.',
      icon: Icons.bedtime_outlined,
      minutes: 1,
    ),
  ],
  StressLevel.elevated: [
    Recommendation(
      title: 'Slow breathing',
      description: 'Breathe in for 4 seconds, out for 6 seconds. A longer exhale helps your body relax.',
      icon: Icons.air,
      minutes: 2,
      action: RecommendationAction.breathing,
    ),
    Recommendation(
      title: 'Take a short break',
      description: "If a conversation feels tense, it's okay to step away for 5 minutes.",
      icon: Icons.pause_circle_outline,
      minutes: 5,
    ),
    Recommendation(
      title: 'Loosen your shoulders',
      description: 'Sit comfortably and slowly roll your shoulders and neck.',
      icon: Icons.self_improvement,
      minutes: 3,
    ),
    Recommendation(
      title: 'Play calming music',
      description: 'Put on a song you find soothing and just listen.',
      icon: Icons.music_note_outlined,
      minutes: 5,
    ),
  ],
  StressLevel.high: [
    Recommendation(
      title: 'Slow breathing',
      description: 'Breathe in for 4 seconds, out for 6 seconds. Follow the circle until you feel steadier.',
      icon: Icons.air,
      minutes: 3,
      action: RecommendationAction.breathing,
    ),
    Recommendation(
      title: 'Ground yourself (5-4-3-2-1)',
      description: 'Name 5 things you see, 4 you can touch, 3 you hear, 2 you smell, and 1 you taste.',
      icon: Icons.visibility_outlined,
      minutes: 3,
    ),
    Recommendation(
      title: 'Talk to someone you trust',
      description: 'Call or message your partner, a friend or a family member.',
      icon: Icons.people_outline,
      minutes: 10,
    ),
    Recommendation(
      title: 'Rest somewhere quiet',
      description: 'Sit or lie down in a calm, comfortable spot for a few minutes.',
      icon: Icons.weekend_outlined,
      minutes: 10,
    ),
  ],
};
