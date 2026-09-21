/// Common utility classes for formatting, string manipulation, and validation.
library;

class DateTimeUtils {
  DateTimeUtils._();

  /// Formats an ISO-8601 string or DateTime into "HH:mm:ss" format.
  /// Returns "--" if null or unparseable.
  static String formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return "--";
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  /// Formats an ISO-8601 string into "HH:mm" short time format.
  static String formatTimeShort(String? iso) {
    if (iso == null || iso.isEmpty) return "";
    final dt = DateTime.tryParse(iso);
    if (dt == null) {
      if (iso.length >= 16) return iso.substring(11, 16);
      return iso;
    }
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  /// Formats a [DateTime] into "YYYY-MM-DD" format.
  static String formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return "$y-$m-$d";
  }

  /// Formats an ISO string into human readable date "YYYY-MM-DD".
  static String formatDateString(String? iso) {
    if (iso == null || iso.isEmpty) return "--";
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return formatDate(dt);
  }
}

class StringUtils {
  StringUtils._();

  /// Converts a text to a safe filename slug (lowercase, alphanumeric and underscores)
  static String slugify(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Returns the uppercase initial of the text or "?" if empty
  static String initials(String? text) {
    if (text == null || text.trim().isEmpty) return "?";
    return text.trim()[0].toUpperCase();
  }

  /// Capitalizes the first letter of a string
  static String capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}

class ValidationUtils {
  ValidationUtils._();

  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  static final RegExp _phoneRegExp = RegExp(
    r'^\+?[0-9\s\-]{7,15}$',
  );

  static final RegExp _usernameRegExp = RegExp(
    r'^[a-zA-Z0-9_]{3,30}$',
  );

  /// Validates standard email address format
  static bool isValidEmail(String? email) {
    if (email == null) return false;
    final trimmed = email.trim();
    if (trimmed.isEmpty) return false;
    return _emailRegExp.hasMatch(trimmed);
  }

  /// Validates phone number (digits, optional +, min 7 digits)
  static bool isValidPhone(String? phone) {
    if (phone == null) return false;
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return false;
    final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return digitsOnly.length >= 7 && _phoneRegExp.hasMatch(trimmed);
  }

  /// Validates register number (non-empty, alphanumeric and hyphens, no whitespace)
  static bool isValidRegisterNumber(String? regNo) {
    if (regNo == null) return false;
    final trimmed = regNo.trim();
    if (trimmed.isEmpty) return false;
    return !trimmed.contains(' ') && trimmed.length >= 2;
  }

  /// Validates username (3-30 characters, alphanumeric and underscore)
  static bool isValidUsername(String? username) {
    if (username == null) return false;
    final trimmed = username.trim();
    return _usernameRegExp.hasMatch(trimmed);
  }

  /// Validates password strength (minimum 6 characters)
  static bool isValidPassword(String? password) {
    if (password == null) return false;
    return password.length >= 6;
  }
}
