#!/bin/bash
#
# CDDL HEADER START
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#
# CDDL HEADER END
#
# Copyright 2019 Saso Kiselkov. All rights reserved.
#

HERE="$(dirname "$0")"

MONTAGE="montage"
CONVERT="convert"
EXTRACT="$HERE/dsf_dem_extract"
RESOLUTION=1024x1024
REMOVE_TEMP=0
NCPUS=$(grep '^processor\>' /proc/cpuinfo | wc -l)

set -e

# Executes up to NCPUS of parallel job tasks using the
# arguments of this function as the command (+args) to run.
function taskq ()
{
	while (( $(jobs | wc -l) > $NCPUS )); do
		wait -n
	done
	"$@" &
}

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
		taskq "$EXTRACT" -o "$DSFFILE" "$TMPDIR/$PNGFILE"
	fi
done
wait

# Fill in empty slots
BASE_X="$(echo ${BASEDIR:3:4} | sed 's/^\([+-]\)0\+\([1-9]\)/\1\2/g')"
BASE_Y="$(echo ${BASEDIR:0:3} | sed 's/^\([+-]\)0\+\([1-9]\)/\1\2/g')"

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
