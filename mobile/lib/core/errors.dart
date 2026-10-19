enum ErrorKind {
  network,
  timeout,
  validation,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  rateLimited,
  membershipRequired,
  subscriptionRequired,
  limitReached,
  verificationRequired,
  paymentFailed,
  mfaRequired,
  suspended,
  maintenance,
  server,
  unknown,
}

/// Typed error produced by the API layer. UI code switches on [kind].
class AppException implements Exception {
  AppException(
    this.kind,
    this.message, {
    this.code,
    this.status,
    this.fieldErrors = const {},
    this.extra,
    this.requestId,
  });

  final ErrorKind kind;
  final String message;
  final String? code;
  final int? status;

  /// field name -> message, from `error.details`.
  final Map<String, String> fieldErrors;
  final Map<String, dynamic>? extra;
  final String? requestId;

  bool get isNetwork => kind == ErrorKind.network || kind == ErrorKind.timeout;

  /// Suggested plans for `membership_required` / `subscription_required`.
  List<Map<String, dynamic>> get suggestedPlans {
    final v = extra?['suggested_plans'];
    return v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];
  }

  static ErrorKind kindFor(String? code, int? status) {
    switch (code) {
      case 'validation_failed':
        return ErrorKind.validation;
      case 'unauthorized':
        return ErrorKind.unauthorized;
      case 'forbidden':
        return ErrorKind.forbidden;
      case 'not_found':
        return ErrorKind.notFound;
      case 'conflict':
        return ErrorKind.conflict;
      case 'rate_limited':
        return ErrorKind.rateLimited;
      case 'membership_required':
        return ErrorKind.membershipRequired;
      case 'subscription_required':
        return ErrorKind.subscriptionRequired;
      case 'limit_reached':
        return ErrorKind.limitReached;
      case 'verification_required':
        return ErrorKind.verificationRequired;
      case 'payment_failed':
        return ErrorKind.paymentFailed;
      case 'mfa_required':
        return ErrorKind.mfaRequired;
      case 'account_suspended':
        return ErrorKind.suspended;
      case 'maintenance':
        return ErrorKind.maintenance;
    }
    if (status == null) return ErrorKind.unknown;
    if (status == 401) return ErrorKind.unauthorized;
    if (status == 403) return ErrorKind.forbidden;
    if (status == 404) return ErrorKind.notFound;
    if (status == 409) return ErrorKind.conflict;
    if (status == 422) return ErrorKind.validation;
    if (status == 429) return ErrorKind.rateLimited;
    if (status >= 500) return ErrorKind.server;
    return ErrorKind.unknown;
  }

  /// Friendly text suitable for snackbars and error states.
  String get userMessage {
    switch (kind) {
      case ErrorKind.network:
        return 'No internet connection. Check your network and try again.';
      case ErrorKind.timeout:
        return 'The server took too long to respond. Please try again.';
      case ErrorKind.server:
        return 'Something went wrong on our side. Please try again shortly.';
      case ErrorKind.rateLimited:
        return 'Too many requests. Please wait a moment and try again.';
      case ErrorKind.maintenance:
        return message.isNotEmpty ? message : 'PETORA is under maintenance. Please check back soon.';
      default:
        return message.isNotEmpty ? message : 'Something went wrong. Please try again.';
    }
  }

  @override
  String toString() => 'AppException($kind, $code, $message)';
}
