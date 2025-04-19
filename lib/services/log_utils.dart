import 'package:logger/logger.dart';
import '../constants/app_constants.dart';

class LogUtils {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
    ),
  );
  static void v(String message) {
    if (AppConstants.DEBUG) {
      _logger.v(message);
    }
  }

  static void d(String message) {
    if (AppConstants.DEBUG) {
      _logger.d(message);
    }
  }

  static void i(String message) {
    if (AppConstants.DEBUG) {
      _logger.i(message);
    }
  }

  static void w(String message) {
    if (AppConstants.DEBUG) {
      _logger.w(message);
    }
  }

  static void e(String message) {
    if (AppConstants.DEBUG) {
      _logger.e(message);
    }
  }
}
