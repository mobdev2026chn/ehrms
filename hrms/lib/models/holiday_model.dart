import 'package:intl/intl.dart';

class Holiday {
  final String? id;
  final String name;
  final DateTime date;
  final String type;

  Holiday({
    this.id,
    required this.name,
    required this.date,
    required this.type,
  });

  factory Holiday.fromJson(Map<String, dynamic> json) {
    return Holiday(
      id: json['_id'],
      name: json['name'] ?? '',
      date: DateTime.parse(json['date']),
      type: json['type'] ?? 'Company', // Defaulting to Company
    );
  }

  String get formattedDate => DateFormat('dd MMM, yyyy').format(date);
  String get dayName => DateFormat('EEEE').format(date); // e.g., Thursday

  bool get isPast {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final holidayDate = DateTime(date.year, date.month, date.day);
    return holidayDate.isBefore(today);
  }

  String get status => isPast ? 'Past' : 'Upcoming';
}
