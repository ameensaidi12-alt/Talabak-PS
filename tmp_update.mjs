const url = 'https://ylpjqejnvhaqbdssjaof.supabase.co/rest/v1';
const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlscGpxZWpudmhhcWJkc3NqYW9mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NjA4MjcsImV4cCI6MjA4NDMzNjgyN30.jrttLiuk5r4woNer1mUMVmQtCq6xI5FcLwMs-DrsfWY';

const headers = {
  'apikey': key,
  'Authorization': `Bearer ${key}`,
  'Content-Type': 'application/json',
  'Prefer': 'return=representation'
};

async function run() {
  try {
    // 1. Get vendor ID
    const res = await fetch(`${url}/vendors?name=eq.فوال الشام`, { headers });
    const vendors = await res.json();
    
    if (!vendors || vendors.length === 0) {
      console.log('Vendor "فوال الشام" not found.');
      return;
    }
    const vendorId = vendors[0].id;
    console.log(`Found vendor ID: ${vendorId}`);

    // 2. Update banner deal_url
    // The user provided the banner ID: 0653d0a9-033b-414c-a550-95ee9edd750a
    const bannerId = '0653d0a9-033b-414c-a550-95ee9edd750a';
    const dealUrl = `${vendorId}#trending`;
    
    const patchRes = await fetch(`${url}/promotions?id=eq.${bannerId}`, {
      method: 'PATCH',
      headers,
      body: JSON.stringify({ deal_url: dealUrl })
    });
    
    const updated = await patchRes.json();
    console.log('Banner updated successfully:', updated);
  } catch(e) {
    console.error(e);
  }
}

run();
