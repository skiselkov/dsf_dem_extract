#!/bin/bash

MONTAGE="montage"
CONVERT="convert"
EXTRACT="./dsf_dem_extract"
RESOLUTION=1024x1024
REMOVE_TEMP=0

set -e

while getopts "r:" o; do
	case "${o}" in
	r)
		RESOLUTION="${OPTARG}x${OPTARG}"
		;;
	*)
		echo "Usage $0 [-r <resolution] <INDIR>" >&2
		exit 1
		;;
	esac
done
shift "$(($OPTIND - 1))"

INDIR="$1"
if [[ "$INDIR" == "" ]]; then
	echo "Missing <INDIR> argument" >&2
	exit 1
fi
shift
BASEDIR="$(basename "$INDIR")"

TMPDIR="demstitch.tmp.$$"
mkdir -p "$TMPDIR"

# Extract all DEMs
for DSFFILE in "$INDIR"/*.dsf; do
	PNGFILE="$(basename "$DSFFILE")"
	PNGFILE="${PNGFILE/%.dsf/.png}"
	if ! [ -f "$TMPDIR/$PNGFILE" ]; then
		echo "[EXTRACT]  $(basename "$DSFFILE")"
		"$EXTRACT" -o "$DSFFILE" "$TMPDIR/$PNGFILE"
	fi
done

# Fill in empty slots
BASE_X=${BASEDIR:3:4}
BASE_Y=${BASEDIR:0:3}
FILESET=""

for (( Y=9; $Y >= 0; Y=$Y - 1)); do
	for (( X=0; $X < 10; X=$X + 1)); do
		DSFFILE="$TMPDIR/$(printf "%+03d%+04d.png" \
		    $(( $BASE_Y + $Y )) $(( $BASE_X + $X )) )"
		if ! [ -f "$DSFFILE" ]; then
			echo "[EMPTY]    $DSFFILE"
			"$EXTRACT" -e "$DSFFILE"
		fi
		FILESET="$FILESET $DSFFILE"
	done
done

MONTAGE_FILE="${TMPDIR}/montage.png"
if ! [ -f "$MONTAGE_FILE" ]; then
	echo "[MONTAGE]  $MONTAGE_FILE"
	"$MONTAGE" -geometry '1200x1200>+0+0' -tile 10x10 $FILESET \
	    "$MONTAGE_FILE"
fi

echo "[CONVERT]  $RESOLUTION"
"$CONVERT" -resize "$RESOLUTION" "$MONTAGE_FILE" "$BASEDIR-hgt.png"

rm -r "$TMPDIR"
