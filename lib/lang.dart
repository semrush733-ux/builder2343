/// Readable names for the language codes found in streams (ISO 639-1 / 639-2).
const Map<String, String> _names = {
  'en': 'English', 'eng': 'English',
  'ur': 'Urdu', 'urd': 'Urdu',
  'hi': 'Hindi', 'hin': 'Hindi',
  'ar': 'Arabic', 'ara': 'Arabic',
  'pa': 'Punjabi', 'pan': 'Punjabi',
  'bn': 'Bengali', 'ben': 'Bengali',
  'fa': 'Persian', 'fas': 'Persian', 'per': 'Persian',
  'ps': 'Pashto', 'pus': 'Pashto',
  'fr': 'French', 'fra': 'French', 'fre': 'French',
  'de': 'German', 'deu': 'German', 'ger': 'German',
  'es': 'Spanish', 'spa': 'Spanish',
  'it': 'Italian', 'ita': 'Italian',
  'pt': 'Portuguese', 'por': 'Portuguese',
  'nl': 'Dutch', 'nld': 'Dutch', 'dut': 'Dutch',
  'pl': 'Polish', 'pol': 'Polish',
  'tr': 'Turkish', 'tur': 'Turkish',
  'ru': 'Russian', 'rus': 'Russian',
  'uk': 'Ukrainian', 'ukr': 'Ukrainian',
  'el': 'Greek', 'ell': 'Greek', 'gre': 'Greek',
  'ro': 'Romanian', 'ron': 'Romanian', 'rum': 'Romanian',
  'sv': 'Swedish', 'swe': 'Swedish',
  'no': 'Norwegian', 'nor': 'Norwegian',
  'da': 'Danish', 'dan': 'Danish',
  'fi': 'Finnish', 'fin': 'Finnish',
  'cs': 'Czech', 'ces': 'Czech', 'cze': 'Czech',
  'hu': 'Hungarian', 'hun': 'Hungarian',
  'sq': 'Albanian', 'sqi': 'Albanian', 'alb': 'Albanian',
  'so': 'Somali', 'som': 'Somali',
  'ta': 'Tamil', 'tam': 'Tamil',
  'te': 'Telugu', 'tel': 'Telugu',
  'ml': 'Malayalam', 'mal': 'Malayalam',
  'zh': 'Chinese', 'zho': 'Chinese', 'chi': 'Chinese',
  'ja': 'Japanese', 'jpn': 'Japanese',
  'ko': 'Korean', 'kor': 'Korean',
  'cy': 'Welsh', 'cym': 'Welsh', 'wel': 'Welsh',
  'ga': 'Irish', 'gle': 'Irish',
  'qaa': 'Original', 'nar': 'Audio description',
};

/// "English", "English - Stereo", "Track 2"...
String trackLabel(String? language, String? title, int number) {
  final code = (language ?? '').trim().toLowerCase();
  final name = _names[code] ?? (code.isEmpty || code == 'und' ? '' : code.toUpperCase());
  final extra = (title ?? '').trim();
  if (name.isEmpty && extra.isEmpty) return 'Track $number';
  if (name.isEmpty) return extra;
  if (extra.isEmpty || extra.toLowerCase() == name.toLowerCase()) return name;
  return '$name  -  $extra';
}
