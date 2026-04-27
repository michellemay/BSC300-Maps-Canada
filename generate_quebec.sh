#!/bin/bash
set -euo pipefail

COUNTRYCODE="CA"
STATE="1100"
VARIANT="${1:-}"

if [ -z "$VARIANT" ] || [ "$VARIANT" -lt 1 ] || [ "$VARIANT" -gt 4 ]; then
  echo "Usage: $0 <variant>"
  echo "  1 = Streets only (no names)"
  echo "  2 = Streets with names"
  echo "  3 = With water"
  echo "  4 = With green stuff"
  exit 1
fi

# Download if not already present
if [ ! -f tmp.pbf ]; then
  echo "==> Downloading Quebec PBF..."
  wget https://download.geofabrik.de/north-america/canada/quebec-latest.osm.pbf -O tmp.pbf
fi

# Convert to o5m if not already done
if [ ! -f tmp.o5m ]; then
  echo "==> Converting to o5m..."
  ./osmosis/osmconvert tmp.pbf -o=tmp.o5m
fi

# ── Filter based on variant ──────────────────────────────────────────────────

COMMON_KEEP=(
  --keep="highway=motorway =motorway_link =primary =primary_link =secondary =secondary_link =tertiary =tertiary_link =trunk =trunk_link =cycleway =living_street =residential =road =track =unclassified"
  --keep="highway=service and ( bicycle=designated or bicycle=yes or bicycle=permissive )"
  --keep="highway=footway and ( bicycle=designated or bicycle=yes or bicycle=permissive )"
  --keep="highway=bridleway and ( bicycle=designated or bicycle=yes or bicycle=permissive )"
  --keep="highway=path and ( bicycle=designated or bicycle=yes or bicycle=permissive )"
  --keep="highway=pedestrian and ( bicycle=designated or bicycle=yes or bicycle=permissive )"
  --keep="highway=unclassified and ( bicycle=designated or bicycle=yes or bicycle=permissive )"
  --keep="sidewalk:*:bicycle=yes"
  --keep="route=bicycle =mtb"
  --keep="cycleway:*=lane :*=track *:=shared_lane *:=share_busway *:=separate *:=crossing *:=shoulder *:=link *:=traffic_island"
  --keep="bicycle_road=yes"
  --keep="cyclestreet=yes"
)

COMMON_MODIFY=" \
  highway=motorway_link to =motorway \
  highway=trunk_link to =primary \
  highway=trunk to =primary \
  highway=primary_link to =primary \
  highway=tertiary_link to =tertiary \
  highway=secondary_link to =secondary \
  highway=trunk_link to =trunk \
  highway=footway to =cycleway \
  highway=bridleway to =cycleway \
  highway=sidewalk to =cycleway \
  highway=path to =cycleway \
  highway=pedestrian to =cycleway \
  highway=unclassified to =cycleway \
  "

EXTRA_KEEP=()
EXTRA_DROP=()
EXTRA_MODIFY=""
TAG_FILE=""

case "$VARIANT" in
  1)
    EXTRA_DROP=(--drop-tags="name= ref=")
    TAG_FILE="tags_minimal_street_only.xml"
    ;;
  2)
    TAG_FILE="tags_minimal_street_only.xml"
    ;;
  3)
    EXTRA_KEEP=(--keep="waterway= landuse= natural=")
    TAG_FILE="tags_with_water.xml"
    ;;
  4)
    EXTRA_KEEP=(--keep="waterway= landuse= natural= leisure=")
    EXTRA_MODIFY=" \
      leisure=garden to landuse=grass \
      leisure=playground to landuse=grass \
      leisure=park to landuse=grass \
      landuse=orchard to =grass \
      landuse=allotments to =grass \
      landuse=farmland to =grass \
      landuse=flowerbed to =grass \
      landuse=meadow to =grass \
      landuse=plant_nursery to =grass \
      landuse=vineyard to =grass \
      landuse=greenfield to =grass \
      landuse=village_green to =grass \
      landuse=greenery to =grass \
      landuse=cemetery to =grass \
      natural=scrub to landuse=grass \
      "
    TAG_FILE="tags_with_green_stuff.xml"
    ;;
esac

echo "==> Filtering (variant $VARIANT)..."
osmosis/osmfilter -v tmp.o5m \
  "${COMMON_KEEP[@]}" \
  ${EXTRA_KEEP[@]+"${EXTRA_KEEP[@]}"} \
  ${EXTRA_DROP[@]+"${EXTRA_DROP[@]}"} \
  --out-o5m > tmp1.o5m

osmosis/osmfilter -v tmp1.o5m \
  --modify-tags="${COMMON_MODIFY}${EXTRA_MODIFY}" \
  --drop-author --drop-version \
  --out-o5m > tmp_filtered.o5m

rm tmp1.o5m

# Crop to polygon AFTER filtering (so --complete-ways doesn't pull in huge water relations)
echo "==> Cropping to polygon..."
./osmosis/osmconvert tmp_filtered.o5m -B=quebec.poly --complete-ways -o=tmp_filtered.pbf
rm tmp_filtered.o5m

echo "==> Building map..."
python3 generate_map.py -i tmp_filtered.pbf -c $COUNTRYCODE -s $STATE -t $TAG_FILE
rm tmp_filtered.pbf

echo "Done!"
