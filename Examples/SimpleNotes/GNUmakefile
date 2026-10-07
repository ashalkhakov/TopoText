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
#
# macOS: the same commands without GNUSTEP_MAKEFILES set go to
# Makefile.apple (the server and the tests; the apps are the Xcode
# project's, TopoText.xcworkspace).

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

SN_FLAGS = -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.0 -fconstant-string-class=NSConstantString \
	-fobjc-exceptions -Wall -Wno-unused-parameter
SN_INCLUDES = -IShared -IAppKit
SN_SYNC_LIBS = -lTopoTextSync -lTopoText -lODataSync -lODataService -lHTTPServerKit -lODataIncrementalStore \
	-lOTelKit -lODataKit -lCoreData -ldispatch

ifneq ($(SN_SERVER_ONLY),yes)
APP_NAME = SimpleNotes
endif
SimpleNotes_OBJC_FILES = AppKit/main.m AppKit/SNAppController.m AppKit/SNWindowController.m AppKit/SNTextView.m AppKit/SNTextSystem.m AppKit/SNTableGrid+System.m AppKit/SNSmartFolderPanel.m AppKit/SNSyncPanel.m AppKit/SNSecretStore.m AppKit/SNSelfTest.m Shared/SNCheck.m \
	Shared/SNModel.m Shared/SNNote.m Shared/SNFolder.m Shared/SNAttachment.m Shared/SNNotes.m Shared/SNSmartFilter.m Shared/SNResolver.m Shared/SNRichText.m Shared/SNTableGrid.m Shared/SNSignIn.m Shared/SNMigration.m
SimpleNotes_INCLUDE_DIRS = $(SN_INCLUDES)
SimpleNotes_OBJCFLAGS = $(SN_FLAGS)
SimpleNotes_GUI_LIBS += $(SN_SYNC_LIBS)
SimpleNotes_XCDATAMODELD_FILES = SimpleNotes.xcdatamodeld
SimpleNotes_RESOURCE_FILES = AppKit/MainMenu.xib AppKit/NotesWindow.xib AppKit/TextPanel.xib AppKit/SmartFolderPanel.xib AppKit/SyncPanel.xib Icons/SimpleNotes.png
# SNNote+CoreDataProperties, SNFolder+CoreDataProperties: generated from
# the model as it builds (Codegen: Category/Extension), as Xcode does.
SimpleNotes_COREDATA_CODEGEN = yes

TOOL_NAME = simplenotes-server
simplenotes-server_OBJC_FILES = Server/SNServer.m Server/SNNotebooks.m Shared/SNModel.m Shared/SNNote.m Shared/SNFolder.m Shared/SNAttachment.m Shared/SNMigration.m
simplenotes-server_XCDATAMODELD_FILES = SimpleNotes.xcdatamodeld
simplenotes-server_COREDATA_CODEGEN = yes
simplenotes-server_INCLUDE_DIRS = $(SN_INCLUDES)
simplenotes-server_OBJCFLAGS = $(SN_FLAGS)
simplenotes-server_TOOL_LIBS += $(SN_SYNC_LIBS)

include $(GNUSTEP_MAKEFILES)/coredata-model.make

-include GNUmakefile.preamble
ifneq ($(SN_SERVER_ONLY),yes)
include $(GNUSTEP_MAKEFILES)/application.make
endif
include $(GNUSTEP_MAKEFILES)/tool.make
-include GNUmakefile.postamble

# The server finds the model beside itself.
after-all::
	rm -rf obj/SimpleNotes.momd && momc SimpleNotes.xcdatamodeld obj/SimpleNotes.momd


check:: all
	$(MAKE) -C Tests run-tests
	Tests/serve-and-check.sh ./obj/simplenotes-server ./SimpleNotes.app/SimpleNotes --check
	Tests/self-test.sh ./obj/simplenotes-server ./SimpleNotes.app/SimpleNotes

endif
