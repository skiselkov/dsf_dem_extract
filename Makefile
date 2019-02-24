
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

# This file must be present and declare LIBACFUTILS to point to
# the built libacfutils repo.
include config.local

OBJS = dsf_dem_extract.o

CFLAGS += $(shell $(LIBACFUTILS)/pkg-config-deps linux-64 --cflags) \
    -I$(LIBACFUTILS)/src -W -Wall -Wextra -Werror -O2 -g
LIBS += $(LIBACFUTILS)/qmake/lin64/libacfutils.a \
    $(shell $(LIBACFUTILS)/pkg-config-deps linux-64 --libs) -lm

all : dsf_dem_extract

clean :
	rm -f dsf_dem_extract $(OBJS)

dsf_dem_extract : $(OBJS)
	$(CC) -o $@ $(OBJS) $(LIBS)
