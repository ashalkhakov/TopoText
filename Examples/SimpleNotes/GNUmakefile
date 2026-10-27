# SimpleNotes: the AppKit app, the server, and their tests.
#
# GNUstep: clang, libobjc2, gnustep-make and -gui, FreeCoreData (its momc
# too), ODataKit, and TopoText installed (make install at the root):
#
#   . /path/to/GNUstep.sh
#   make                     SimpleNotes.app, simplenotes-server
#   make check               the tests; two devices against the server;
#                            the app driven from within (--self-test)
#   openapp ./SimpleNotes.app
#   ./obj/simplenotes-server -StoreURL notes.sqlite -Port 8080 -Localhost NO
#   make SN_SERVER_ONLY=yes  the server alone, on Foundation only (no
#                            gnustep-gui: Docker/server.Dockerfile)
#   make install             the app, and the server with its model beside it
#
# macOS: Makefile.apple (the server and the tests; the apps are the Xcode
# project's, TopoText.xcworkspace).

ifeq ($(GNUSTEP_MAKEFILES),)
$(error Set GNUSTEP_MAKEFILES (source GNUstep.sh). macOS: make -f Makefile.apple)
endif

include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
OBJC = clang

SN_FLAGS = -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 -fconstant-string-class=NSConstantString \
	-fobjc-exceptions -Wall -Wno-unused-parameter
# TopoText's libraries from the tree they are built in (the root's
# GNUmakefile builds them first), headers and all.
TT_ROOT = $(CURDIR)/../..
SN_INCLUDES = -IShared -IAppKit -I$(TT_ROOT)/Sources/TopoText/include -I$(TT_ROOT)/Sources/TopoTextSync/include
SN_LIB_DIRS = -L$(TT_ROOT)/obj
SN_RUN = LD_LIBRARY_PATH="$(TT_ROOT)/obj$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" PATH="$(TT_ROOT)/obj:$$PATH"
SN_SYNC_LIBS = -lTopoTextSync -lTopoText -lODataSync -lODataService -lHTTPServerKit -lODataIncrementalStore \
	-lOTelKit -lODataKit -lCoreData -ldispatch

# The system's half of what differs (SNMemory.h, SNWatchdog.h, SNPeers.h's
# SNLocalAddress): glibc's and POSIX's (SNMemory.m), or Windows' own
# (SNMemory-Windows.m), whose network adapters are IP Helper's. The server
# opens FreeCoreData's SQL stores with dlopen: dlfcn-win32 there.
ifneq ($(filter mingw% windows%,$(GNUSTEP_TARGET_OS)),)
SN_SYSTEM = -Windows
SimpleNotes_GUI_LIBS += -liphlpapi -lws2_32
simplenotes-server_TOOL_LIBS += -ldl
# FreeCoreData's SQL stores as Windows names their DLLs.
simplenotes-server_CPPFLAGS += '-DSN_STORE_LIBRARY_FORMAT=@"%@-0.dll"'
else
SN_SYSTEM =
endif

ifneq ($(SN_SERVER_ONLY),yes)
APP_NAME = SimpleNotes
endif
SimpleNotes_OBJC_FILES = AppKit/main.m AppKit/SNAppController.m AppKit/SNWindowController.m AppKit/SNTextView.m AppKit/SNTextSystem.m AppKit/SNTableGrid+System.m AppKit/SNSmartFolderPanel.m AppKit/SNSyncPanel.m AppKit/SNPeersWindow.m AppKit/SNTransferPanel.m AppKit/SNGallery.m AppKit/SNVersionsPanel.m AppKit/SNMemory$(SN_SYSTEM).m AppKit/SNWatchdog$(SN_SYSTEM).m AppKit/SNUpdater.m AppKit/SNSecretStore.m AppKit/SNSelfTest.m Shared/SNCheck.m \
	Shared/SNModel.m Shared/SNNote.m Shared/SNFolder.m Shared/SNAttachment.m Shared/SNNotes.m Shared/SNSmartFilter.m Shared/SNResolver.m Shared/SNRichText.m Shared/SNThumbnails.m Shared/SNShares.m Shared/SNMarkdownEscape.m Shared/SNTableGrid.m Shared/SNSignIn.m Shared/SNPeers.m Shared/SNLocalAddress$(SN_SYSTEM).m Shared/SNMigration.m \
	Shared/SNMarkdown.m Shared/SNZip.m Shared/SNTransfer.m
SimpleNotes_INCLUDE_DIRS = $(SN_INCLUDES)
SimpleNotes_LIB_DIRS = $(SN_LIB_DIRS)
SimpleNotes_OBJCFLAGS = $(SN_FLAGS)
SimpleNotes_GUI_LIBS += $(SN_SYNC_LIBS) -lz
SimpleNotes_XCDATAMODELD_FILES = SimpleNotes.xcdatamodeld
SimpleNotes_RESOURCE_FILES = AppKit/MainMenu.xib AppKit/NotesWindow.xib AppKit/TextPanel.xib AppKit/SmartFolderPanel.xib AppKit/SyncPanel.xib AppKit/DevicesNearby.xib AppKit/TransferPanel.xib AppKit/UpdatePanel.xib AppKit/AttachmentsWindow.xib AppKit/VersionsPanel.xib Icons/SimpleNotes.png
# SNNote+CoreDataProperties, SNFolder+CoreDataProperties: generated from
# the model as it builds (Codegen: Category/Extension), as Xcode does.
SimpleNotes_COREDATA_CODEGEN = yes

TOOL_NAME = simplenotes-server
simplenotes-server_OBJC_FILES = Server/SNServer.m Server/SNNotebooks.m Server/SNVersions.m Shared/SNModel.m Shared/SNNote.m Shared/SNFolder.m Shared/SNAttachment.m Shared/SNMigration.m
simplenotes-server_XCDATAMODELD_FILES = SimpleNotes.xcdatamodeld
simplenotes-server_COREDATA_CODEGEN = yes
simplenotes-server_INCLUDE_DIRS = $(SN_INCLUDES)
simplenotes-server_LIB_DIRS = $(SN_LIB_DIRS)
simplenotes-server_OBJCFLAGS = $(SN_FLAGS)
simplenotes-server_TOOL_LIBS += $(SN_SYNC_LIBS)

include $(GNUSTEP_MAKEFILES)/coredata-model.make

-include GNUmakefile.preamble
ifneq ($(SN_SERVER_ONLY),yes)
include $(GNUSTEP_MAKEFILES)/application.make
endif
include $(GNUSTEP_MAKEFILES)/tool.make
-include GNUmakefile.postamble

# The server finds the model beside itself: built, and installed.
after-all::
	rm -rf obj/SimpleNotes.momd && momc SimpleNotes.xcdatamodeld obj/SimpleNotes.momd

after-install::
	@server=$$(find "$(GNUSTEP_TOOLS)" -type f -name simplenotes-server$(EXEEXT) -perm -u+x | head -n 1); \
	  [ -n "$$server" ] || { echo "install: no simplenotes-server$(EXEEXT) under $(GNUSTEP_TOOLS)"; exit 1; }; \
	  rm -rf "$$(dirname "$$server")/SimpleNotes.momd" && cp -R obj/SimpleNotes.momd "$$(dirname "$$server")/"


check:: all
	$(MAKE) -C Tests run-tests
	$(SN_RUN) Tests/serve-and-check.sh ./obj/simplenotes-server ./SimpleNotes.app/SimpleNotes --check
	$(SN_RUN) Tests/move-and-check.sh ./obj/simplenotes-server
	$(SN_RUN) Tests/self-test.sh ./obj/simplenotes-server ./SimpleNotes.app/SimpleNotes
