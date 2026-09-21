#!/bin/bash
# Genera un GeoJSON de las construcciones mapeadas como afectadas por el sismo del Palmar
# (damage:event=2026ColombiaEarthquake-Palmar / Q140984463) desde Overpass, para consumir
# en uMap como datos remotos. Pensado para correr por cron (p. ej. cada hora).
#
# Uso:  ./genera_palmar_geojson.sh /ruta/web/palmar_afectadas.geojson
# Datos: © colaboradores de OpenStreetMap, ODbL.

set -u
OUT="${1:-/var/www/html/palmar_afectadas.geojson}"
TMP="$(mktemp)"
UA="AC3-palmar-generator (contact@ac3.org.co)"
Q='[out:json][timeout:180];nwr["damage:event"="2026ColombiaEarthquake-Palmar"];out geom;'

# Servidores Overpass a intentar, en orden (el primero que responda con datos gana).
for EP in \
  "https://overpass-api.de/api/interpreter" \
  "https://overpass.kumi.systems/api/interpreter" \
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter" ; do
  code=$(curl -s --max-time 200 -H "User-Agent: $UA" -G "$EP" \
         --data-urlencode "data=$Q" -o "$TMP" -w "%{http_code}")
  if [ "$code" = "200" ] && python3 -c "import json,sys; sys.exit(0 if json.load(open('$TMP')).get('elements') else 1)" 2>/dev/null; then
    echo "$(date '+%F %T')  OK desde $EP"
    break
  fi
  echo "$(date '+%F %T')  fallo/vacio en $EP (HTTP $code)"
done

# Convertir la respuesta Overpass (out geom) a GeoJSON: nodos->Point, vías cerradas->Polygon,
# vías abiertas->LineString. (Relaciones se omiten; son pocas.)
python3 - "$TMP" "$OUT" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
d = json.load(open(src))
feats = []
for e in d.get("elements", []):
    props = {**e.get("tags", {}), "osm_type": e["type"], "osm_id": e["id"]}
    if e["type"] == "node":
        geom = {"type": "Point", "coordinates": [e["lon"], e["lat"]]}
    elif e["type"] == "way" and e.get("geometry"):
        coords = [[p["lon"], p["lat"]] for p in e["geometry"]]
        if len(coords) >= 4 and coords[0] == coords[-1]:
            geom = {"type": "Polygon", "coordinates": [coords]}
        else:
            geom = {"type": "LineString", "coordinates": coords}
    else:
        continue
    feats.append({"type": "Feature", "geometry": geom, "properties": props})
fc = {"type": "FeatureCollection",
      "attribution": "© OpenStreetMap contributors, ODbL",
      "features": feats}
json.dump(fc, open(dst, "w"), ensure_ascii=False)
print(f"{__import__('datetime').datetime.now():%F %T}  escrito {dst}: {len(feats)} features")
PY
rm -f "$TMP"
