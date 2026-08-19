/**
 * Reverse geocoding: lat/lng -> address.
 * Prefers Google Geocoding API when a server key is configured,
 * falls back to OpenStreetMap Nominatim if Google is unavailable.
 */

const GEOCODE_TIMEOUT_MS = 3000;

function getGoogleMapsKey() {
  return (
    process.env.GOOGLE_MAPS_API_KEY ||
    process.env.GOOGLE_GEOCODING_API_KEY ||
    ''
  ).trim();
}

function getAddressComponent(components, desiredTypes) {
  if (!Array.isArray(components)) return '';
  for (const component of components) {
    const types = Array.isArray(component?.types) ? component.types : [];
    if (desiredTypes.some((type) => types.includes(type))) {
      return component?.long_name || '';
    }
  }
  return '';
}

function getGeometryLocationType(result) {
  if (!result || typeof result !== 'object') return '';
  const geometry = result.geometry;
  if (!geometry || typeof geometry !== 'object') return '';
  return geometry.location_type || '';
}

function rankGoogleResult(result) {
  const locationType = getGeometryLocationType(result);
  switch (locationType) {
    case 'ROOFTOP':
      return 0;
    case 'RANGE_INTERPOLATED':
      return 1;
    case 'GEOMETRIC_CENTER':
      return 2;
    case 'APPROXIMATE':
      return 3;
    default:
      return 4;
  }
}

function pickBestGoogleResult(results) {
  if (!Array.isArray(results) || results.length === 0) return null;
  const candidates = results.filter((result) => result && typeof result === 'object');
  if (!candidates.length) return null;
  candidates.sort((a, b) => {
    const rankDiff = rankGoogleResult(a) - rankGoogleResult(b);
    if (rankDiff !== 0) return rankDiff;
    const partialA = a.partial_match === true ? 1 : 0;
    const partialB = b.partial_match === true ? 1 : 0;
    return partialA - partialB;
  });
  return candidates[0];
}

async function reverseGeocodeWithGoogle(lat, lng) {
  const apiKey = getGoogleMapsKey();
  if (!apiKey) return null;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), GEOCODE_TIMEOUT_MS);
  try {
    const url =
      `https://maps.googleapis.com/maps/api/geocode/json` +
      `?latlng=${lat},${lng}` +
      `&key=${apiKey}`;

    const res = await fetch(url, {
      headers: { 'User-Agent': 'HRMS-Geo-Tracking/1.0' },
      signal: controller.signal,
    });
    if (!res.ok) return null;

    const data = await res.json();
    if (data?.status !== 'OK' || !Array.isArray(data.results) || !data.results.length) {
      return null;
    }

    const result = pickBestGoogleResult(data.results) || {};
    const components = result.address_components || [];
    const formattedAddress = result.formatted_address || '';

    return {
      address: formattedAddress,
      fullAddress: formattedAddress,
      city:
        getAddressComponent(components, ['locality']) ||
        getAddressComponent(components, ['postal_town']) ||
        getAddressComponent(components, ['administrative_area_level_2']) ||
        getAddressComponent(components, ['administrative_area_level_1']),
      area:
        getAddressComponent(components, [
          'sublocality_level_1',
          'sublocality',
          'neighborhood',
          'premise',
        ]) || getAddressComponent(components, ['route']),
      pincode: getAddressComponent(components, ['postal_code']),
    };
  } catch (err) {
    if (process.env.NODE_ENV !== 'production') {
      console.warn('[Geocoding] Google reverse geocode failed:', err.message);
    }
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

async function reverseGeocodeWithNominatim(lat, lng) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), GEOCODE_TIMEOUT_MS);
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json`;
    const res = await fetch(url, {
      headers: { 'User-Agent': 'HRMS-Geo-Tracking/1.0' },
      signal: controller.signal,
    });
    if (!res.ok) return null;

    const data = await res.json();
    const addr = data.address || {};
    const displayName = data.display_name || '';
    return {
      address: displayName,
      fullAddress: displayName,
      city: addr.city || addr.town || addr.village || addr.county || '',
      area: addr.suburb || addr.neighbourhood || addr.locality || '',
      pincode: addr.postcode || '',
    };
  } catch (err) {
    if (process.env.NODE_ENV !== 'production') {
      console.warn('[Geocoding] Nominatim reverse geocode failed:', err.message);
    }
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

async function reverseGeocode(lat, lng) {
  const googleResult = await reverseGeocodeWithGoogle(lat, lng);
  if (googleResult) return googleResult;
  return reverseGeocodeWithNominatim(lat, lng);
}

module.exports = { reverseGeocode };
