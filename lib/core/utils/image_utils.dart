class ImageUtils {
  static const String _supabaseUrl = 'ylpjqejnvhaqbdssjaof.supabase.co';
  static const String _proxyUrl = 'talabak.meegramsx.workers.dev';

  /// Proxies a Supabase image URL through Cloudflare Workers to save on egress costs.
  static String? proxyUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    
    // Proxy if it's a Supabase storage URL
    if (url.contains(_supabaseUrl)) {
      return url.replaceFirst(_supabaseUrl, _proxyUrl);
    }
    
    return url;
  }
}
