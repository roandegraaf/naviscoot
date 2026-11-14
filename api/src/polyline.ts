export type LatLon = [lat: number, lon: number];

export function decodePolyline6(encoded: string): LatLon[] {
  const coords: LatLon[] = [];
  let index = 0;
  let lat = 0;
  let lon = 0;
  while (index < encoded.length) {
    for (const axis of [0, 1]) {
      let shift = 0;
      let result = 0;
      let byte: number;
      do {
        byte = encoded.charCodeAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      const delta = result & 1 ? ~(result >> 1) : result >> 1;
      if (axis === 0) lat += delta;
      else lon += delta;
    }
    coords.push([lat / 1e6, lon / 1e6]);
  }
  return coords;
}

export function encodePolyline6(coords: LatLon[]): string {
  let out = "";
  let prevLat = 0;
  let prevLon = 0;
  for (const [lat, lon] of coords) {
    const ilat = Math.round(lat * 1e6);
    const ilon = Math.round(lon * 1e6);
    out += encodeValue(ilat - prevLat) + encodeValue(ilon - prevLon);
    prevLat = ilat;
    prevLon = ilon;
  }
  return out;
}

function encodeValue(value: number): string {
  let v = value < 0 ? ~(value << 1) : value << 1;
  let out = "";
  while (v >= 0x20) {
    out += String.fromCharCode((0x20 | (v & 0x1f)) + 63);
    v >>= 5;
  }
  return out + String.fromCharCode(v + 63);
}
