import 'dart:typed_data';
import 'dart:math';

double decodeDouble(String hex, int offset) {
  final b = Uint8List(8);
  for (int i = 0; i < 8; i++) b[i] = int.parse(hex.substring(offset + i * 2, offset + i * 2 + 2), radix: 16);
  return ByteData.view(b.buffer).getFloat64(0, Endian.little);
}

double dist(double lat1, double lng1, double lat2, double lng2) {
  const R = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat/2)*sin(dLat/2) + cos(lat1*pi/180)*cos(lat2*pi/180)*sin(dLng/2)*sin(dLng/2);
  return R * 2 * atan2(sqrt(a), sqrt(1-a));
}

void main() {
  final uLat = 32.372146, uLng = 35.069100;
  
  final areas = {
    'طولكرم':    '0101000020E6100000FE18319FB98441403FFDD0D759274040',
    'الشعراوية': '0101000020E6100000FF5F86071489414005B142A8B42F4040',
    'عتيل':      '0101000020E6100000B87CD1957089414082A54489222F4040',
    'زيتا':      '0101000020E6100000EB5819E18F864140044A20F26E314040',
    'الناصرة':   '0101000020E61000006666666666A641409A99999999594040',
    'ام الفحم':  '0101000020E610000033333333339341400000000000404040',
    'باقة الغربية':'0101000020E6100000CDCCCCCCCC8C41406666666666264040',
    'حيفا':      '0101000020E610000000000000008041406666666666664040',
    'رهط':       '0101000020E61000008FC2F5285C6F41401F85EB51B85E3F40',
    'جديدة المكر':'0101000020E61000007B14AE47E19A4140D7A3703D0A774040',
    'رام الله':  '0101000020E61000001895D409689A4140F31FD26F5FE73F40',
    'الخليل':    '0101000020E6100000B22E6EA3018C41407FD93D7958883F40',
    'دير الغصون':'0101000020E6100000DC33CB4AEA8941402DFEA076FB2C4040',
    'القدس':     '0101000020E61000001B0DE02D90A04140A3923A014D1C4040',
  };
  
  print("موقعك: $uLat, $uLng\n");
  
  final results = <MapEntry<String, double>>[];
  for (final e in areas.entries) {
    final hex = e.value;
    final lng = decodeDouble(hex, 18); // X
    final lat = decodeDouble(hex, 34); // Y
    final d = dist(uLat, uLng, lat, lng);
    results.add(MapEntry(e.key, d));
    print("${e.key}: lat=$lat, lng=$lng -> ${(d/1000).toStringAsFixed(2)} كم");
  }
  
  results.sort((a, b) => a.value.compareTo(b.value));
  print("\n🏆 الأقرب لموقعك: ${results.first.key} (${(results.first.value/1000).toStringAsFixed(2)} كم)");
  print("🥈 الثاني: ${results[1].key} (${(results[1].value/1000).toStringAsFixed(2)} كم)");
  print("🥉 الثالث: ${results[2].key} (${(results[2].value/1000).toStringAsFixed(2)} كم)");
}
