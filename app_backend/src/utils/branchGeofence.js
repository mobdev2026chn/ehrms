/**
 * Shared branch geofence parsing — must match attendance check-in / check-out validation.
 */

function toFiniteNumber(value) {
  if (value === null || value === undefined) return null;
  const num = typeof value === 'number' ? value : parseFloat(String(value));
  return Number.isFinite(num) ? num : null;
}

/** @returns {number} distance in meters */
function haversineDistanceM(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Returns geofence validation targets for a branch.
 * Priority:
 * 1) If `branch.geofence.enabled === true` and `branch.geofence.locations[]` exists, use those circles.
 * 2) Otherwise fall back to the single `branch.geofence.latitude/longitude/radius` circle.
 * 3) Legacy: if no `geofence.enabled`, but `branch.latitude/longitude` exist, use them.
 */
function getBranchGeofenceTargets(branch) {
  const gf = branch?.geofence;
  const geofenceEnabled = gf?.enabled === true;

  if (!geofenceEnabled) {
    const legacyLat = toFiniteNumber(branch?.latitude);
    const legacyLng = toFiniteNumber(branch?.longitude);
    if (legacyLat != null && legacyLng != null) {
      const radius = toFiniteNumber(branch?.radius) ?? 100;
      return {
        enabled: true,
        targets: [
          {
            latitude: legacyLat,
            longitude: legacyLng,
            radius,
            label: branch?.branchName || 'Assigned Branch',
          },
        ],
      };
    }
    return { enabled: false, targets: [] };
  }

  const locations = gf?.locations;
  if (Array.isArray(locations) && locations.length > 0) {
    const targets = locations
      .map((l) => {
        const latitude = toFiniteNumber(l?.latitude ?? l?.lat);
        const longitude = toFiniteNumber(l?.longitude ?? l?.lng);
        const radius = toFiniteNumber(l?.radius) ?? toFiniteNumber(gf?.radius) ?? 100;
        const label = l?.label ?? l?.name ?? null;
        if (latitude == null || longitude == null) return null;
        return { latitude, longitude, radius, label };
      })
      .filter(Boolean);
    return { enabled: true, targets };
  }

  const latitude = toFiniteNumber(gf?.latitude);
  const longitude = toFiniteNumber(gf?.longitude);
  const radius = toFiniteNumber(gf?.radius) ?? 100;
  if (latitude == null || longitude == null) return { enabled: true, targets: [] };
  return {
    enabled: true,
    targets: [
      {
        latitude,
        longitude,
        radius,
        label: branch?.branchName || 'Assigned Branch',
      },
    ],
  };
}

const MAX_ACCURACY_BUFFER_M = 80;

/**
 * True if (lat,lng) falls within any branch geofence circle (same rules as check-in).
 * Optional GPS accuracy (m) expands allowed radius slightly to reduce boundary flicker.
 */
function isLatLngInsideBranchGeofence(branch, lat, lng, accuracyM = 0) {
  const { enabled, targets } = getBranchGeofenceTargets(branch);
  if (!enabled || targets.length === 0) return false;
  const latN = Number(lat);
  const lngN = Number(lng);
  if (!Number.isFinite(latN) || !Number.isFinite(lngN)) return false;
  const acc = Number(accuracyM);
  const buffer = Number.isFinite(acc) && acc > 0 ? Math.min(acc, MAX_ACCURACY_BUFFER_M) : 0;

  for (const t of targets) {
    const distM = haversineDistanceM(latN, lngN, t.latitude, t.longitude);
    if (distM <= t.radius + buffer) return true;
  }
  return false;
}

module.exports = {
  toFiniteNumber,
  getBranchGeofenceTargets,
  isLatLngInsideBranchGeofence,
};
