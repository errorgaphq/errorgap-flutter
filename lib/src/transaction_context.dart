import 'dart:async';
import 'dart:math';

/// The zone key holding the current transaction id.
const Symbol _transactionIdKey = #errorgapTransactionId;

/// The id of the APM transaction the current zone is running in, if any.
///
/// Errors reported while it is set carry it as `context.transaction_id`, so
/// errorgap links each error to the interaction that raised it. Zone values
/// follow async work started inside [withErrorgapTransaction] and never leak
/// into concurrent work.
String? currentErrorgapTransactionId() =>
    Zone.current[_transactionIdKey] as String?;

/// Run [body] as part of the transaction with [id].
R withErrorgapTransaction<R>(String id, R Function() body) =>
    runZoned(body, zoneValues: <Object?, Object?>{_transactionIdKey: id});

final Random _random = Random.secure();

/// A random (version 4) UUID.
String newErrorgapTransactionId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
