bool isAdvertiserRequestApproved(String status) {
  return status.trim().toLowerCase() == 'approved';
}

bool isAdvertiserApplicationLocked(String status) {
  final normalizedStatus = status.trim().toLowerCase();
  return normalizedStatus == 'pending' || normalizedStatus == 'approved';
}
