# TopoText, a rich text CRDT, and TopoTextSync, its part in an ODataSync
# store (ODataKit).
#
# GNUstep: clang, libobjc2 (the gnustep-2.0 runtime) and gnustep-make; for
# TopoTextSync, FreeCoreData and ODataKit installed
# (https://github.com/ashalkhakov/ODataKit, make install there):
#
#   . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
#   make && make install
#   make test
#   make WITH_SYNC=no      TopoText alone: Foundation, nothing else
#
# macOS: the same commands, without GNUSTEP_MAKEFILES set, go to
# Makefile.apple (clang, Apple's Foundation, Xcode's xctest).

ifeq ($(GNUSTEP_MAKEFILES),)
ifeq ($(shell uname -s),Darwin)
include Makefile.apple
else
$(error Set GNUSTEP_MAKEFILES (source GNUstep.sh).)
endif
else

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
TopoTextSync_OBJC_FILES = Sources/TopoTextSync/TTSyncResolver.m
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

endif
