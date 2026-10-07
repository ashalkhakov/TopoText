# SimpleNotes' tests on GNUstep (tools-xctest): the devices against the
# service in one process, and the text view's binding (gnustep-gui; run
# under xvfb-run when there is no display: fonts come from the backend).
#
#   make -C Tests run-tests

ifeq ($(GNUSTEP_MAKEFILES),)
$(error Set GNUSTEP_MAKEFILES (source GNUstep.sh).)
endif

include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
OBJC = clang

BUNDLE_NAME = SimpleNotesTests
SimpleNotesTests_NEEDS_GUI = yes
SimpleNotesTests_OBJC_FILES = SNNotesTests.m SNTextBindingTests.m SNMigrationTests.m \
	../Shared/SNModel.m ../Shared/SNNote.m ../Shared/SNFolder.m ../Shared/SNAttachment.m ../Shared/SNNotes.m ../Shared/SNResolver.m ../Shared/SNRichText.m ../Shared/SNMigration.m
SimpleNotesTests_INCLUDE_DIRS = -I../Shared
SimpleNotesTests_OBJCFLAGS = -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 -fconstant-string-class=NSConstantString \
	-fobjc-exceptions -Wall -Wno-unused-parameter
SimpleNotesTests_BUNDLE_LIBS += -lTopoTextSync -lTopoText -lODataSync -lODataService -lHTTPServerKit -lODataIncrementalStore \
	-lOTelKit -lODataKit -lCoreData -lXCTest -lgnustep-gui -ldispatch
SimpleNotesTests_XCDATAMODELD_FILES = ../SimpleNotes.xcdatamodeld
SimpleNotesTests_COREDATA_CODEGEN = yes
include $(GNUSTEP_MAKEFILES)/coredata-model.make

XCTEST ?= xctest
XVFB := $(shell command -v xvfb-run >/dev/null 2>&1 && [ -z "$$DISPLAY" ] && echo xvfb-run -a)

.PHONY: run-tests
run-tests: all
	$(XVFB) $(XCTEST) SimpleNotesTests.bundle

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/bundle.make
-include GNUmakefile.postamble
