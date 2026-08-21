import 'package:flutter/foundation.dart';

enum LogDomain { auth, crypto, sync, network, general, search }

enum LogType { error, info, warn, log }

enum LogColor {
  black,
  red,
  green,
  yellow,
  blue,
  magenta,
  cyan,
  white,
  brightBlack,
  brightRed,
  brightGreen,
  brightYellow,
  brightBlue,
  brightMagenta,
  brightCyan,
  brightWhite
}

final logColorMap = {
  LogColor.black: 30,
  LogColor.red: 31,
  LogColor.green: 32,
  LogColor.yellow: 33,
  LogColor.blue: 34,
  LogColor.magenta: 35,
  LogColor.cyan: 36,
  LogColor.white: 37,
  LogColor.brightBlack: 90,
  LogColor.brightRed: 91,
  LogColor.brightGreen: 92,
  LogColor.brightYellow: 93,
  LogColor.brightBlue: 94,
  LogColor.brightMagenta: 95,
  LogColor.brightCyan: 96,
  LogColor.brightWhite: 97
};

class Log {
  static void i(String msg) => debugPrint('\x1B[34mℹ️  $msg\x1B[0m');

  static void w(String msg) => debugPrint('\x1B[33m⚠️  $msg\x1B[0m');

  static void e(String msg) => debugPrint('\x1B[31m❌ $msg\x1B[0m');

  static void ok(String msg) => debugPrint('\x1B[32m✅ $msg\x1B[0m');

  static String getMessage(String msg, LogColor color) =>
      '\x1B[${logColorMap[color]}m$msg\x1B[0m';
}

class KragLogger {
  static void info(LogDomain domain, String message) {
    _log(domain, LogType.info, message);
  }

  static void warn(LogDomain domain, String message) {
    _log(domain, LogType.warn, message);
  }

  static void error(LogDomain domain, String message,
      [Object? error, StackTrace? stackTrace]) {
    _log(domain, LogType.error, message);
    if (error != null) {
      debugPrint('  Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('  Stack Trace:\n$stackTrace');
    }
  }

  static void _log(LogDomain domain, LogType level, String message) {
    if (kDebugMode) {
      final color = _getlevelColor(level);
      final timestamp = Log.getMessage(
          DateTime.now().toIso8601String(), LogColor.brightBlack);
      final domainTag =
          Log.getMessage(_getDomainTag(domain), LogColor.brightBlue);
      final levelTag =
          Log.getMessage(_getlevelTag(level), LogColor.brightMagenta);
      final messageTag = Log.getMessage(message, color);
      final msg = '**[$timestamp]** [$domainTag] $levelTag:\r\n$messageTag';
      debugPrint(msg);
    }
  }

  static String _getlevelTag(LogType level) {
    switch (level) {
      case LogType.error:
        return 'ERROR';
      case LogType.info:
        return 'INFO';
      case LogType.warn:
        return 'WARN';
      case LogType.log:
        return 'LOG';
    }
  }

  static LogColor _getlevelColor(LogType level) {
    switch (level) {
      case LogType.error:
        return LogColor.red;
      case LogType.info:
        return LogColor.brightCyan;
      case LogType.warn:
        return LogColor.yellow;
      case LogType.log:
        return LogColor.white;
    }
  }

  static String _getDomainTag(LogDomain domain) {
    switch (domain) {
      case LogDomain.auth:
        return 'AUTH';
      case LogDomain.crypto:
        return 'CRYPTO';
      case LogDomain.sync:
        return '** SYNC **';
      case LogDomain.network:
        return 'NETWORK';
      case LogDomain.general:
        return 'GENERAL';
      case LogDomain.search:
        return 'SEARCH';
    }
  }
}
