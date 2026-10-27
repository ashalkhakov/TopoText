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
SimpleNotesTests_OBJC_FILES = SNNotesTests.m $(SN_PEER_TESTS) SNTextBindingTests.m SNMigrationTests.m SNSignInTests.m SNTransferTests.m ../Server/SNNotebooks.m ../Server/SNVersions.m ../Shared/SNSignIn.m ../Shared/SNPeers.m ../Shared/SNLocalAddress$(SN_SYSTEM).m ../AppKit/SNSecretStore.m \
	../Shared/SNModel.m ../Shared/SNNote.m ../Shared/SNFolder.m ../Shared/SNAttachment.m ../Shared/SNNotes.m ../Shared/SNSmartFilter.m ../Shared/SNResolver.m ../Shared/SNRichText.m ../Shared/SNMigration.m \
	../Shared/SNTableGrid.m ../Shared/SNMarkdown.m ../Shared/SNMarkdownEscape.m ../Shared/SNShares.m ../Shared/SNZip.m ../Shared/SNTransfer.m ../AppKit/SNTextSystem.m ../AppKit/SNTableGrid+System.m
# TopoText's libraries from the tree they are built in.
TT_ROOT = $(CURDIR)/../../..
SimpleNotesTests_INCLUDE_DIRS = -I../Shared -I../Server -I$(TT_ROOT)/Sources/TopoText/include -I$(TT_ROOT)/Sources/TopoTextSync/include
SimpleNotesTests_LIB_DIRS = -L$(TT_ROOT)/obj
SimpleNotesTests_OBJCFLAGS = -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 -fconstant-string-class=NSConstantString \
	-fobjc-exceptions -Wall -Wno-unused-parameter
SimpleNotesTests_BUNDLE_LIBS += -lTopoTextSync -lTopoText -lODataSync -lODataService -lHTTPServerKit -lODataIncrementalStore \
	-lOTelKit -lODataKit -lCoreData -lXCTest -lgnustep-gui -ldispatch -lz
# The system's half of SNLocalAddress (../GNUmakefile). Devices nearby,
# and the server's peer tokens: not on Windows yet (ODataSync's peers are
# not there), so neither are their tests.
ifneq ($(filter mingw% windows%,$(GNUSTEP_TARGET_OS)),)
SN_SYSTEM = -Windows
SN_PEER_TESTS =
SimpleNotesTests_BUNDLE_LIBS += -liphlpapi -lws2_32
else
SN_SYSTEM =
SN_PEER_TESTS = SNNotesTests+Peers.m
endif
SimpleNotesTests_XCDATAMODELD_FILES = ../SimpleNotes.xcdatamodeld
SimpleNotesTests_COREDATA_CODEGEN = yes
include $(GNUSTEP_MAKEFILES)/coredata-model.make

XCTEST ?= xctest
XVFB := $(shell command -v xvfb-run >/dev/null 2>&1 && [ -z "$$DISPLAY" ] && echo xvfb-run -a)

.PHONY: run-tests
run-tests: all
	LD_LIBRARY_PATH="$(TT_ROOT)/obj$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" PATH="$(TT_ROOT)/obj:$$PATH" $(XVFB) $(XCTEST) SimpleNotesTests.bundle

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/bundle.make
-include GNUmakefile.postamble
