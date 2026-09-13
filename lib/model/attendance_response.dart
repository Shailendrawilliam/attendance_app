class AttendanceResponse {
  final String status;
  final bool inserted;
  final int id;
  final bool flagged;
  final double? computedDistance;
  final String currentState;
  final int totalSecondsToday;
  final String totalText;

  AttendanceResponse({
    required this.status,
    required this.inserted,
    required this.id,
    required this.flagged,
    required this.computedDistance,
    required this.currentState,
    required this.totalSecondsToday,
    required this.totalText,
  });

  factory AttendanceResponse.fromJson(Map<String, dynamic> json) {
    return AttendanceResponse(
      status: json['status'] ?? '',
      inserted: json['inserted'] ?? false,
      id: json['id'] ?? 0,
      flagged: json['flagged'] ?? false,
      computedDistance: json['computed_distance'] == null
          ? null
          : (json['computed_distance'] as num).toDouble(),
      currentState: json['current_state'] ?? '',
      totalSecondsToday: json['total_seconds_today'] ?? 0,
      totalText: json['total_text'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "status": status,
      "inserted": inserted,
      "id": id,
      "flagged": flagged,
      "computed_distance": computedDistance,
      "current_state": currentState,
      "total_seconds_today": totalSecondsToday,
      "total_text": totalText,
    };
  }
}
