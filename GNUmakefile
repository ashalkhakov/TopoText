# TopoText, a rich text CRDT, and TopoTextSync, its part in an ODataSync
# store (ODataKit); and SimpleNotes (Examples/SimpleNotes), the app and its
# server, on them.
#
# GNUstep: clang, libobjc2 (the gnustep-2.0 runtime) and gnustep-make; for
# TopoTextSync and SimpleNotes, FreeCoreData and ODataKit installed (the
# releases .github/pins.env names):
#
#   . /path/to/GNUstep.sh
#   make                 the libraries, then SimpleNotes and its server
#   make check           the tests (below)
#   make install         the libraries, SimpleNotes and its server
#   make WITH_SYNC=no    TopoText alone: Foundation, nothing else
#
# Apple's platforms: Makefile.apple.

ifeq ($(GNUSTEP_MAKEFILES),)
$(error Set GNUSTEP_MAKEFILES (source GNUstep.sh). Apple's platforms: make -f Makefile.apple)
endif

include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
OBJC = clang
ifeq ($(findstring gcc,$(CC)),gcc)
$(error TopoText needs clang and libobjc2. GCC's libobjc has no ARC.)
endif

WITH_SYNC ?= yes

TT_INCLUDE_DIRS = -ISources/TopoText/include -ISources/TopoText/include/TopoText -ISources/TopoText \
	-ISources/TopoTextSync/include -ISources/TopoTextSync/include/TopoTextSync
TT_OBJCFLAGS = -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 \
	-fconstant-string-class=NSConstantString -fobjc-exceptions -Wall -Wno-unused-parameter

LIBRARY_NAME = TopoText
ifeq ($(WITH_SYNC),yes)
LIBRARY_NAME += TopoTextSync
endif

TopoText_NEEDS_GUI = no
TopoText_OBJC_FILES = \
	Sources/TopoText/TopoText.m \
	Sources/TopoText/TTCoding.m \
	Sources/TopoText/TTTable.m
TopoText_HEADER_FILES = TopoText.h
TopoText_HEADER_FILES_DIR = Sources/TopoText/include/TopoText
TopoText_HEADER_FILES_INSTALL_DIR = TopoText
TopoText_INCLUDE_DIRS = $(TT_INCLUDE_DIRS)
TopoText_OBJCFLAGS += $(TT_OBJCFLAGS)
TopoText_LIBRARIES_DEPEND_UPON += -ldispatch

TopoTextSync_NEEDS_GUI = no
TopoTextSync_OBJC_FILES = Sources/TopoTextSync/TTSyncResolver.m Sources/TopoTextSync/TTSyncMerger.m
TopoTextSync_HEADER_FILES = TopoTextSync.h
TopoTextSync_HEADER_FILES_DIR = Sources/TopoTextSync/include/TopoTextSync
TopoTextSync_HEADER_FILES_INSTALL_DIR = TopoTextSync
TopoTextSync_INCLUDE_DIRS = $(TT_INCLUDE_DIRS)
TopoTextSync_LIB_DIRS = -L./obj
TopoTextSync_OBJCFLAGS += $(TT_OBJCFLAGS)
TopoTextSync_LIBRARIES_DEPEND_UPON += -lTopoText -lODataSync -lODataKit -lCoreData -ldispatch

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/library.make
-include GNUmakefile.postamble

# make -j: TopoTextSync links against TopoText.
TopoTextSync.all.library.variables: TopoText.all.library.variables

.PHONY: test
test: all
	$(MAKE) -C Tests run-tests WITH_SYNC=$(WITH_SYNC)

# SimpleNotes, on the libraries (with TopoTextSync only).
ifeq ($(WITH_SYNC),yes)
after-all::
	$(MAKE) -C Examples/SimpleNotes

after-install::
	$(MAKE) -C Examples/SimpleNotes install

after-clean::
	$(MAKE) -C Examples/SimpleNotes clean
endif

# make check:
#   TopoText alone (WITH_SYNC=no), built apart, in build/alone
#   the libraries' unit tests
#   SimpleNotes': its unit tests, two devices through its server, the
#     server moved from one store to another, and the app driven from
#     within (Xvfb when there is no display)
#   its server on PostgreSQL and MariaDB, given by their URLs (POSTGRES_URL,
#     MARIADB_URL); without one, skipped, but not in CI, where a missing
#     server is a failure. The move onto PostgreSQL needs a database made
#     for it: by docker exec, when POSTGRES_CONTAINER names the server's.
SN = Examples/SimpleNotes
SN_RUN = LD_LIBRARY_PATH="$(CURDIR)/obj$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"
check::
	$(MAKE) WITH_SYNC=no GNUSTEP_BUILD_DIR=$(CURDIR)/build/alone
	$(MAKE) -C Tests run-tests WITH_SYNC=$(WITH_SYNC)
	$(MAKE) -C $(SN) check
	@for server in POSTGRES_URL MARIADB_URL; do \
	  if [ -z "$$(printenv $$server)" ]; then \
	    if [ -n "$$CI" ]; then echo "check: $$server is not set; the server's database checks need it in CI"; exit 1; fi; \
	    echo "check: no $$server: the server's checks on it are skipped"; \
	  fi; \
	done
	@if [ -n "$$POSTGRES_URL" ]; then cd $(SN) && \
	  $(SN_RUN) SN_STORE_ARGS="-StoreType PostgreSQL -StoreURL $$POSTGRES_URL" \
	    Tests/serve-and-check.sh ./obj/simplenotes-server ./SimpleNotes.app/SimpleNotes --check || exit 1; fi
	@if [ -n "$$MARIADB_URL" ]; then cd $(SN) && \
	  $(SN_RUN) SN_STORE_ARGS="-StoreType MariaDB -StoreURL $$MARIADB_URL" SN_CHECK_PORT=18081 \
	    Tests/serve-and-check.sh ./obj/simplenotes-server ./SimpleNotes.app/SimpleNotes --check || exit 1; fi
	@if [ -n "$$POSTGRES_URL" ] && [ -n "$$POSTGRES_CONTAINER" ]; then \
	  docker exec "$$POSTGRES_CONTAINER" psql -U postgres -c 'DROP DATABASE IF EXISTS moved' -c 'CREATE DATABASE moved' > /dev/null && \
	  cd $(SN) && $(SN_RUN) Tests/move-and-check.sh ./obj/simplenotes-server -StoreType PostgreSQL -StoreURL "$${POSTGRES_URL%/*}/moved" || exit 1; fi
