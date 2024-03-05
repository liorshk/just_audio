import 'package:flutter/foundation.dart';

bool isLogEnabled = false;

void logHLS(String? message) {
  if (!isLogEnabled) {
    return;
  }
  debugPrint('[HLS lib] $message');
}
