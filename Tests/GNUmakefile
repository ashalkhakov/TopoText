# The XCTest suites on GNUstep (tools-xctest, https://github.com/gnustep/tools-xctest):
#
#   make -C Tests run-tests        or, from the top: make test
#
# TopoTextSyncTests runs ODataSync in the process, against an ODataService
# and peer servers: FreeCoreData and ODataKit installed. WITH_SYNC=no leaves
# it out.

ifeq ($(GNUSTEP_MAKEFILES),)
$(error Set GNUSTEP_MAKEFILES (source GNUstep.sh).)
endif

include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
OBJC = clang
WITH_SYNC ?= yes

BUNDLE_NAME = TopoTextTests
ifeq ($(WITH_SYNC),yes)
BUNDLE_NAME += TopoTextSyncTests
endif

TT_INCLUDE_DIRS = -I../Sources/TopoText/include -I../Sources/TopoText/include/TopoText \
	-I../Sources/TopoTextSync/include -I../Sources/TopoTextSync/include/TopoTextSync
ADDITIONAL_OBJCFLAGS += -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 \
	-fconstant-string-class=NSConstantString -fobjc-exceptions -Wall -Wno-unused-parameter

TopoTextTests_NEEDS_GUI = no
TopoTextTests_OBJC_FILES = TopoTextTests.m TopoTextFuzzTests.m TTTableTests.m TTUndoTests.m
TopoTextTests_INCLUDE_DIRS = $(TT_INCLUDE_DIRS)
TopoTextTests_LIB_DIRS = -L../obj
TopoTextTests_OBJC_LIBS += -lTopoText -lXCTest

TopoTextSyncTests_NEEDS_GUI = no
TopoTextSyncTests_OBJC_FILES = TopoTextSyncTests.m
TopoTextSyncTests_INCLUDE_DIRS = $(TT_INCLUDE_DIRS)
TopoTextSyncTests_LIB_DIRS = -L../obj
TopoTextSyncTests_OBJC_LIBS += -lTopoTextSync -lTopoText -lODataSync -lODataService -lHTTPServerKit -lODataIncrementalStore \
	-lOTelKit -lODataKit -lCoreData -lXCTest

XCTEST ?= xctest

.PHONY: run-tests
run-tests: all
	set -e; for b in $(BUNDLE_NAME); do \
	  LD_LIBRARY_PATH="$(CURDIR)/../obj$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" $(XCTEST) "$$b.bundle"; \
	done

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/bundle.make
-include GNUmakefile.postamble
