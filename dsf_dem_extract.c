/*
 * CDDL HEADER START
 *
 * This file and its contents are supplied under the terms of the
 * Common Development and Distribution License ("CDDL"), version 1.0.
 * You may only use this file in accordance with the terms of version
 * 1.0 of the CDDL.
 *
 * A full copy of the text of the CDDL should have accompanied this
 * source.  A copy of the CDDL is also available via the Internet at
 * http://www.illumos.org/license/CDDL.
 *
 * CDDL HEADER END
*/
/*
 * Copyright 2019 Saso Kiselkov. All rights reserved.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <getopt.h>
#include <arpa/inet.h>

#include <acfutils/assert.h>
#include <acfutils/dsf.h>
#include <acfutils/math.h>
#include <acfutils/png.h>
#include <acfutils/safe_alloc.h>

#define	ELEV_MET2SAMPLE(met) \
	(round(255 * iter_fract((met), 8848, -418, B_TRUE)))

static inline double
demd_read(const dsf_atom_t *demi, const dsf_atom_t *demd,
    unsigned row, unsigned col)
{
	double v = 0;

#define	DEMD_READ(data_type, val) \
	do { \
		(val) = ((data_type *)demd->payload)[row * \
		    demi->demi_atom.width + col] * \
		    demi->demi_atom.scale + demi->demi_atom.offset; \
	} while (0)
	switch (demi->demi_atom.flags & DEMI_DATA_MASK) {
	case DEMI_DATA_FP32:
		DEMD_READ(float, v);
		break;
	case DEMI_DATA_SINT:
		switch (demi->demi_atom.bpp) {
		case 1:
			DEMD_READ(int8_t, v);
			break;
		case 2:
			DEMD_READ(int16_t, v);
			break;
		case 4:
			DEMD_READ(int32_t, v);
			break;
		}
		break;
	case DEMI_DATA_UINT:
		switch (demi->demi_atom.bpp) {
		case 1:
			DEMD_READ(uint8_t, v);
			break;
		case 2:
			DEMD_READ(uint16_t, v);
			break;
		case 4:
			DEMD_READ(uint32_t, v);
			break;
		}
		break;
	default:
		VERIFY(0);
	}
#undef	DEMD_READ

	return (v);
}

static bool_t
dem_dsf_check(const dsf_t *dsf, const dsf_atom_t **demi_p,
    const dsf_atom_t **demd_p)
{
	enum { DSF_DEMI_MIN_RES = 32 };
	return (
	    (*demi_p = dsf_lookup(dsf, DSF_ATOM_DEMS, 0, DSF_ATOM_DEMI,
	    0, 0)) != NULL &&
	    (*demd_p = dsf_lookup(dsf, DSF_ATOM_DEMS, 0, DSF_ATOM_DEMD,
	    0, 0)) != NULL &&
	    (*demi_p)->demi_atom.width >= DSF_DEMI_MIN_RES &&
	    (*demi_p)->demi_atom.height >= DSF_DEMI_MIN_RES);
}

static dsf_t *
load_dem_dsf(const char *filename, const dsf_atom_t **demi_p,
    const dsf_atom_t **demd_p)
{
	dsf_t *dsf = dsf_init(filename);

	if (dsf != NULL) {
		if (dem_dsf_check(dsf, demi_p, demd_p))
			return (dsf);
		fprintf(stderr, "%s: invalid or missing DEM data\n", filename);
		dsf_fini(dsf);
	}

	return (NULL);
}

#define	SHORT_IMG

static void
dem2png(const char *infile, const char *outfile, bool_t del_overlap,
    bool_t bpp_16)
{
	unsigned dsf_width, dsf_height;
	dsf_t *dsf = NULL;
	const dsf_atom_t *demi = NULL, *demd = NULL;

	dsf = load_dem_dsf(infile, &demi, &demd);
	if (dsf == NULL)
		exit(EXIT_FAILURE);

	dsf_width = demi->demi_atom.width;
	dsf_height = demi->demi_atom.height;
	if (del_overlap) {
		dsf_width--;
		dsf_height--;
	}

	if (bpp_16) {
		uint16_t *pixels =
		    safe_malloc(dsf_width * dsf_height * sizeof (*pixels));

		for (unsigned y = 0; y < dsf_height; y++) {
			for (unsigned x = 0; x < dsf_width; x++) {
				pixels[y * dsf_width + x] =
				    htons(demd_read(demi, demd,
				    dsf_height - y - 1, x) + INT16_MAX);
			}
		}
		png_write_to_file_grey16(outfile, dsf_width, dsf_height,
		    pixels);
		free(pixels);
	} else {
		uint8_t *pixels =
		    safe_malloc(dsf_width * dsf_height * sizeof (*pixels));

		for (unsigned y = 0; y < dsf_height; y++) {
			for (unsigned x = 0; x < dsf_width; x++) {
				pixels[y * dsf_width + x] =
				    ELEV_MET2SAMPLE(demd_read(demi, demd,
					dsf_height - y - 1, x));
			}
		}
		png_write_to_file_grey8(outfile, dsf_width, dsf_height,
		    pixels);
		free(pixels);
	}

	dsf_fini(dsf);
}

static void
make_empty_png(const char *filename, unsigned width, unsigned height,
    bool_t bpp_16)
{
	if (bpp_16) {
		int16_t *pixels = safe_malloc(width * height *
		    sizeof (*pixels));
		for (unsigned i = 0; i < width * height; i++)
			pixels[i] = htons(INT16_MAX);
		png_write_to_file_grey16(filename, width, height, pixels);
		free(pixels);
	} else {
		uint8_t *pixels = safe_malloc(width * height *
		    sizeof (*pixels));
		for (unsigned i = 0; i < width * height; i++)
			pixels[i] = ELEV_MET2SAMPLE(0);
		png_write_to_file_grey8(filename, width, height, pixels);
		free(pixels);
	}
}

int
main(int argc, char *argv[])
{
	bool_t del_overlap = B_FALSE, empty_file = B_FALSE;
	const char *in_filename = NULL, *out_filename = NULL;
	int c;
	bool_t bpp_16 = B_FALSE;

	while ((c = getopt(argc, argv, "hoes")) != -1) {
		switch (c) {
		case 'h':
			printf("Usage: %s <filename.dsf> <filename.png>\n",
			    argv[0]);
			return (0);
		case 'o':
			del_overlap = B_TRUE;
			break;
		case 'e':
			empty_file = B_TRUE;
			break;
		case 's':
			bpp_16 = B_TRUE;
			break;
		default:
			fprintf(stderr, "Try \"%s -h\" for help.\n", argv[0]);
			return (1);
		}
	}
	if ((empty_file && optind >= argc) ||
	    (!empty_file && optind + 1 >= argc)) {
		fprintf(stderr, "Missing arguments. Try \"%s -h\" for help.\n",
		    argv[0]);
		return (1);
	}
	in_filename = argv[optind++];
	if (empty_file) {
		make_empty_png(in_filename, 1200, 1200, bpp_16);
		return (0);
	}
	out_filename = argv[optind++];

	dem2png(in_filename, out_filename, del_overlap, bpp_16);

	return (0);
}
