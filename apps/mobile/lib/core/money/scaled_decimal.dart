class ScaledDecimal {
  const ScaledDecimal._();

  static int toMinor(dynamic value) => toScaled(value, 2);
  static int toMilli(dynamic value) => toScaled(value, 3);

  static int toScaled(dynamic value, int fractionDigits) {
    if (value == null) return 0;
    var text = value.toString().trim();
    if (text.isEmpty) return 0;
    final negative = text.startsWith('-');
    if (negative || text.startsWith('+')) text = text.substring(1);
    final parts = text.split('.');
    final whole = int.tryParse(parts.first.isEmpty ? '0' : parts.first) ?? 0;
    var fraction = parts.length > 1 ? parts[1] : '';
    if (fraction.length > fractionDigits) {
      final kept = fraction.substring(0, fractionDigits);
      final nextDigit = int.tryParse(fraction[fractionDigits]) ?? 0;
      var scaled = whole * _pow10(fractionDigits) + int.parse(kept.isEmpty ? '0' : kept);
      if (nextDigit >= 5) scaled += 1;
      return negative ? -scaled : scaled;
    }
    fraction = fraction.padRight(fractionDigits, '0');
    final scaled = whole * _pow10(fractionDigits) + int.parse(fraction.isEmpty ? '0' : fraction);
    return negative ? -scaled : scaled;
  }

  static String fromMinor(int minor) => fromScaled(minor, 2);
  static String fromMilli(int milli) => fromScaled(milli, 3, trimTrailingZeros: true);

  static String fromScaled(
    int value,
    int fractionDigits, {
    bool trimTrailingZeros = false,
  }) {
    final negative = value < 0;
    final absolute = value.abs();
    final divisor = _pow10(fractionDigits);
    final whole = absolute ~/ divisor;
    var fraction = (absolute % divisor).toString().padLeft(fractionDigits, '0');
    if (trimTrailingZeros) {
      fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    }
    final sign = negative ? '-' : '';
    return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}

class Loti {
  const Loti._();

  static String formatMinor(int minor) {
    final value = ScaledDecimal.fromMinor(minor);
    final parts = value.split('.');
    final negative = parts.first.startsWith('-');
    final whole = negative ? parts.first.substring(1) : parts.first;
    final buffer = StringBuffer();
    for (var index = 0; index < whole.length; index++) {
      if (index > 0 && (whole.length - index) % 3 == 0) buffer.write(',');
      buffer.write(whole[index]);
    }
    final sign = negative ? '-' : '';
    return 'M $sign${buffer.toString()}.${parts.length > 1 ? parts[1] : '00'}';
  }
}
