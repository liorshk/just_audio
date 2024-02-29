import 'package:flutter/foundation.dart';

bool isLogEnabled = true;

void logHLS(String? message) {
  if (!isLogEnabled) {
    return;
  }
  debugPrint('[HLS lib] $message');
}
