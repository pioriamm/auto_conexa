class MovideskTicketInfo {
  const MovideskTicketInfo({
    required this.id,
    required this.status,
  });

  final int? id;
  final String status;
}

class MovideskPersonInfo {
  const MovideskPersonInfo({
    required this.id,
    required this.businessName,
    required this.personType,
    required this.profileType,
  });

  final String id;
  final String businessName;
  final int personType;
  final int profileType;
}

class ProcessingException implements Exception {
  const ProcessingException(this.message);

  final String message;

  @override
  String toString() => message;
}
