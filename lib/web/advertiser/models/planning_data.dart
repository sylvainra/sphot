class PlanningData {
  const PlanningData({
    this.durationLabel,
    this.startDate,
    this.endDate,
    this.exclusiveReservation = false,
    this.availabilityConfirmed = false,
  });

  final String? durationLabel;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool exclusiveReservation;
  final bool availabilityConfirmed;

  bool get isComplete =>
      durationLabel != null &&
      startDate != null &&
      endDate != null &&
      exclusiveReservation &&
      availabilityConfirmed;
}
