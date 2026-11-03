// Spaced repetition and exam readiness, ported from
// Margin/Services/Learning/LearningEngines.swift.

import 'dart:math';

import '../data/dates.dart';

enum ReviewGrade {
  again(0, 'Nochmal'),
  hard(3, 'Schwer'),
  good(4, 'Gut'),
  easy(5, 'Leicht');

  const ReviewGrade(this.quality, this.title);
  final int quality;
  final String title;
}

class CardSchedule {
  const CardSchedule({this.ease = 2.5, this.intervalDays = 0, this.repetitions = 0, this.lapses = 0, required this.due});

  final double ease;
  final int intervalDays;
  final int repetitions;
  final int lapses;
  final DateTime due;
}

/// SM-2 (the algorithm behind Anki and SuperMemo): cards you know come back
/// later and later, cards you don't know come back the same day.
abstract final class SpacedRepetition {
  static CardSchedule review(CardSchedule card, ReviewGrade grade, DateTime now) {
    final q = grade.quality.toDouble();
    if (grade == ReviewGrade.again) {
      return CardSchedule(
        ease: _floor(card.ease - 0.2),
        intervalDays: 0,
        repetitions: 0,
        lapses: card.lapses + 1,
        due: now.add(const Duration(minutes: 10)),
      );
    }
    final repetitions = card.repetitions + 1;
    final int interval;
    switch (repetitions) {
      case 1:
        interval = grade == ReviewGrade.easy ? 3 : 1;
      case 2:
        interval = grade == ReviewGrade.easy ? 6 : (grade == ReviewGrade.hard ? 2 : 4);
      default:
        final factor = grade == ReviewGrade.hard ? 0.8 : (grade == ReviewGrade.easy ? 1.3 : 1.0);
        final grown = (card.intervalDays * card.ease * factor).round();
        interval = grown > card.intervalDays + 1 ? grown : card.intervalDays + 1;
    }
    return CardSchedule(
      ease: _floor(card.ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))),
      intervalDays: interval,
      repetitions: repetitions,
      lapses: card.lapses,
      due: addDays(startOfDay(now), interval),
    );
  }

  static double _floor(double ease) => ease < 1.3 ? 1.3 : ease;
}

class ReadinessInput {
  const ReadinessInput({
    required this.id,
    this.importance = 1,
    this.understanding = 0,
    this.completion = 0,
    this.lastStudied,
    this.scores = const [],
  });

  final String id;
  final int importance;
  final int understanding;
  final double completion;
  final DateTime? lastStudied;

  /// Practice scores 0 … 1, newest first.
  final List<double> scores;
}

class TopicReadiness {
  const TopicReadiness(this.id, this.score);
  final String id;
  final double score;
}

/// Exam readiness from understanding, practice, finished material and how
/// long ago a topic was studied.
abstract final class Readiness {
  static (double, List<TopicReadiness>) evaluate(List<ReadinessInput> topics, DateTime now) {
    if (topics.isEmpty) return (0.0, const <TopicReadiness>[]);
    var weighted = 0.0, weights = 0.0;
    final results = <TopicReadiness>[];
    for (final topic in topics) {
      final understanding = max(0, min(4, topic.understanding)) / 4;
      final recent = topic.scores.take(3).toList();
      final practice = recent.isEmpty ? understanding * 0.6 : recent.reduce((a, b) => a + b) / recent.length;
      final last = topic.lastStudied;
      final daysAgo = last == null ? null : daysBetween(last, now);
      final double decay = daysAgo == null || daysAgo <= 5 ? 1.0 : max(0.7, 1 - (daysAgo - 5) / 80);
      final double score = min(1.0, (0.55 * understanding + 0.25 * practice + 0.2 * topic.completion) * decay);
      final weight = const [0.75, 1.0, 1.3][max(0, min(2, topic.importance))];
      weighted += score * weight;
      weights += weight;
      results.add(TopicReadiness(topic.id, score));
    }
    return (weighted / max(weights, 0.0001), results);
  }
}
