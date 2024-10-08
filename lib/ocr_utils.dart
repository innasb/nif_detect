class OCRUtils {
  static String? extractNIF(String text) {
    final nifPattern = RegExp(r'NIF\s*:\s*(\d{20})');
    final match = nifPattern.firstMatch(text);
    return match?.group(1);
  }

  static String? extractActivityCode(String text) {
    final activityCodePattern = RegExp(r'(?<!\S)(\d{6})(?!\S)');
    final match = activityCodePattern.firstMatch(text);
    if (match != null) {
      String extractedCode = match.group(1)!;
      return _validActivityCodes.contains(extractedCode) ? extractedCode : "Invalid Activity Code: $extractedCode";
    }
    return null;
  }

  static const List<String> _validActivityCodes = [
    "507215", "610010", "610005", "507214", "507213", "501114"
  ];
}
