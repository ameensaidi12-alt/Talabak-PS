/**
 * Cloudflare Worker: Supabase Image Proxy & Cache
 * Domain: talabak.meegramsx.workers.dev
 */

const SUPABASE_URL = 'https://ylpjqejnvhaqbdssjaof.supabase.co';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    
    // Construct the destination Supabase URL
    // We expect requests like: https://talabak.meegramsx.workers.dev/storage/v1/object/public/...
    const destinationUrl = `${SUPABASE_URL}${url.pathname}${url.search}`;

    // Check Cloudflare Cache first
    const cache = caches.default;
    let response = await cache.match(request);

    if (!response) {
      console.log(`Cache miss for: ${destinationUrl}. Fetching from Supabase...`);
      
      const originalResponse = await fetch(destinationUrl, {
        headers: request.headers,
      });

      // Clone the response to modify headers and save to cache
      response = new Response(originalResponse.body, originalResponse);

      // Add Cache-Control headers to tell Cloudflare (and browsers) to cache for a long time
      // 30 days internal cache, 1 day browser cache
      response.headers.set('Cache-Control', 'public, s-maxage=2592000, max-age=86400');
      response.headers.set('Access-Control-Allow-Origin', '*');
      
      // Store in cache (only if status is 200)
      if (originalResponse.status === 200) {
        ctx.waitUntil(cache.put(request, response.clone()));
      }
    } else {
      console.log(`Cache hit for: ${destinationUrl}`);
    }

    return response;
  },
};
