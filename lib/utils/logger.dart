import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as log_package;

/// A logging utility for the application.
/// 
/// This class provides methods for logging messages at different levels.
/// Uses the 'logger' package for proper log handling in both debug and production.
class Logger {
  final String _tag;
  late final log_package.Logger _logger;
  
  /// Creates a new logger with the specified tag.
  /// 
  /// The tag is used to identify the source of the log message.
  Logger(this._tag) {
    _logger = log_package.Logger(
      printer: log_package.PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 5,
        lineLength: 80,
        colors: true,
        printEmojis: true,
        dateTimeFormat: log_package.DateTimeFormat.none,
      ),
    );
  }
  
  /// Logs a debug message.
  /// 
  /// Debug messages are only logged in debug builds.
  void d(String message) {
    if (kDebugMode) {
      _logger.d('[$_tag] $message');
    }
  }
  
  /// Logs an info message.
  void i(String message) {
    _logger.i('[$_tag] $message');
  }
  
  /// Logs a warning message.
  void w(String message) {
    _logger.w('[$_tag] $message');
  }
  
  /// Logs an error message.
  void e(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e('[$_tag] $message', error: error, stackTrace: stackTrace);
  }
}