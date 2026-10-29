/// Helpers for the "Quality" button of the player.
///
/// An IPTV server sends each channel or film in one fixed quality; a player cannot ask for a
/// smaller version of the same stream. What it can do:
///  * switch between the versions of a channel that the server lists separately
///    ("Sky Sports FHD", "Sky Sports HD", "Sky Sports SD"), and
///  * pick a variant when the stream itself carries several (adaptive HLS).

final _tag = RegExp(
    r'\b(8k|4k|uhd|fhd|full\s*hd|hd|sd|hevc|h\.?265|h\.?264|2160p?|1440p?|1080p?|720p?|576p?|480p?|360p?|50\s*fps|60\s*fps|raw|backup|low|multi)\b',
    caseSensitive: false);
final _noise = RegExp(r'[^a-z0-9؀-ۿ]+');

/// "PK | GEO NEWS FHD" and "PK | Geo News HD*" both give "pk geo news".
String channelBaseName(String name) {
  return name.toLowerCase().replaceAll(_tag, ' ').replaceAll(_noise, ' ').trim();
}

/// Quality written in a channel name, best first when sorted by [qualityRank].
String qualityInName(String name) {
  final n = name.toLowerCase();
  bool has(String pattern) => RegExp('\\b($pattern)\\b').hasMatch(n);
  if (has('8k')) return '8K';
  if (has('4k|uhd|2160p?')) return '4K';
  if (has('1440p?')) return '1440p';
  if (has('fhd|full\\s*hd|1080p?')) return 'Full HD 1080p';
  if (has('hd|720p?')) return 'HD 720p';
  if (has('576p?')) return 'SD 576p';
  if (has('sd|480p?|low')) return 'SD 480p';
  if (has('360p?')) return '360p';
  return 'Standard';
}

int qualityRank(String label) {
  const order = ['8K', '4K', '1440p', 'Full HD 1080p', 'HD 720p', 'Standard', 'SD 576p', 'SD 480p', '360p'];
  final i = order.indexOf(label);
  return i < 0 ? order.length : i;
}

/// Name for a picture height: 2160 -> "4K", 1080 -> "Full HD 1080p"...
String qualityOfHeight(int height) {
  if (height <= 0) return '';
  if (height >= 4000) return '8K';
  if (height >= 2000) return '4K';
  if (height >= 1300) return '1440p';
  if (height >= 1000) return 'Full HD 1080p';
  if (height >= 700) return 'HD 720p';
  if (height >= 560) return 'SD 576p';
  if (height >= 400) return 'SD 480p';
  return '${height}p';
}

/// Positions in [names] of the other versions of the channel at [current], best quality first.
List<int> otherVersions(List<String> names, int current) {
  if (current < 0 || current >= names.length) return const [];
  final base = channelBaseName(names[current]);
  if (base.length < 2) return const [];
  final found = <int>[];
  for (var i = 0; i < names.length; i++) {
    if (i != current && channelBaseName(names[i]) == base) found.add(i);
  }
  found.sort((a, b) => qualityRank(qualityInName(names[a])).compareTo(qualityRank(qualityInName(names[b]))));
  return found;
}
