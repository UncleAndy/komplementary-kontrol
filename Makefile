CC ?= gcc
PKG_CONFIG ?= pkg-config
RM=rm
CP=cp
MKDIR=mkdir -p
STRIP=strip

PREFIX ?= /usr
DESTDIR ?=

SRCDIR = src
BUILDDIR = obj

vpath %.c $(SRCDIR)

MAPPINGS_PATH = $(PREFIX)/share/komplementary-kontrol/mappings
PRESETS_PATH = $(PREFIX)/share/komplementary-kontrol/presets

# --- Library discovery -------------------------------------------------------
# Prefer pkg-config: on NixOS the headers and libraries live in the store and
# there is no /usr/include or /usr/lib to fall back on. The hard-coded names
# are kept as a fallback for systems without pkg-config / .pc files.
ALSA_PKG   ?= alsa
HIDAPI_PKG ?= hidapi-libusb

ALSA_CFLAGS   = $(shell $(PKG_CONFIG) --cflags $(ALSA_PKG) 2>/dev/null)
ALSA_LIBS     = $(shell $(PKG_CONFIG) --libs $(ALSA_PKG) 2>/dev/null || echo -lasound)
HIDAPI_CFLAGS = $(shell $(PKG_CONFIG) --cflags $(HIDAPI_PKG) 2>/dev/null)
HIDAPI_LIBS   = $(shell $(PKG_CONFIG) --libs $(HIDAPI_PKG) 2>/dev/null || echo -lhidapi-libusb)
# hidapi installs its header as <prefix>/include/hidapi/hidapi.h and the source
# includes it as <hidapi/hidapi.h>, but the shipped .pc only advertises
# -I<prefix>/include/hidapi. Ask for the bare include root too so that both
# upstream (meson) and distro layouts compile.
HIDAPI_INC    = $(shell $(PKG_CONFIG) --variable=includedir $(HIDAPI_PKG) 2>/dev/null)

CFLAGS+=-Wall
CFLAGS+=$(ALSA_CFLAGS) $(HIDAPI_CFLAGS) $(addprefix -I,$(strip $(HIDAPI_INC)))
CFLAGS+=-DMAPPINGS_PATH=\"$(MAPPINGS_PATH)\"
CFLAGS+=-DPRESETS_PATH=\"$(PRESETS_PATH)\"

# Linking flags for `komplement` tool.
KOMPLEMENT_LFLAGS=$(HIDAPI_LIBS) $(ALSA_LIBS)

# Linker flags for `konfigure` tool.
KONFIGURE_LFLAGS=$(ALSA_LIBS)

KOMPLEMENT_SOURCES=$(SRCDIR)/komplement.c $(SRCDIR)/button_names.c $(SRCDIR)/uinput_stuff.c\
	$(SRCDIR)/mapping.c $(SRCDIR)/config.c $(SRCDIR)/hid.c $(SRCDIR)/hid_dump.c\
	$(SRCDIR)/button_leds.c $(SRCDIR)/alsa.c $(SRCDIR)/mmc_stuff.c

KONFIGURE_SOURCES=$(SRCDIR)/konfigure.c $(SRCDIR)/konfigure_parser.c

KOMPLEMENT_OBJECTS=$(KOMPLEMENT_SOURCES:src/%.c=obj/%.o)
KONFIGURE_OBJECTS=$(KONFIGURE_SOURCES:src/%.c=obj/%.o)

all: checkdir komplement konfigure

checkdir: $(BUILDDIR)

$(BUILDDIR):
	$(MKDIR) $@

install: komplement konfigure
	$(MKDIR) $(DESTDIR)$(MAPPINGS_PATH)
	$(CP) mappings/*.map $(DESTDIR)$(MAPPINGS_PATH)
	$(MKDIR) $(DESTDIR)$(PRESETS_PATH)
	$(CP) presets/*.pst $(DESTDIR)$(PRESETS_PATH)
	$(STRIP) komplement
	$(STRIP) konfigure
	$(MKDIR) $(DESTDIR)$(PREFIX)/bin
	$(CP) komplement $(DESTDIR)$(PREFIX)/bin/
	$(CP) konfigure $(DESTDIR)$(PREFIX)/bin/

uninstall:
	$(RM) -f $(DESTDIR)$(PREFIX)/bin/komplement
	$(RM) -f $(DESTDIR)$(PREFIX)/bin/konfigure
	@echo "NOTE: The files in $(DESTDIR)$(MAPPINGS_PATH) and $(DESTDIR)$(PRESETS_PATH) have not been deleted."

clean:
	$(RM) -f $(BUILDDIR)/*.o komplement konfigure

$(BUILDDIR)/%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/alsa.o: $(SRCDIR)/alsa.h $(SRCDIR)/alsa.c $(SRCDIR)/defs.h

$(BUILDDIR)/mmc_stuff.o: $(SRCDIR)/mmc_stuff.h $(SRCDIR)/mmc_stuff.c $(SRCDIR)/defs.h

$(BUILDDIR)/config.o: $(SRCDIR)/config.h $(SRCDIR)/config.c $(SRCDIR)/uinput_stuff.h $(SRCDIR)/button_names.h $(SRCDIR)/defs.h $(SRCDIR)/mmc_stuff.h

$(BUILDDIR)/mapping.o: $(SRCDIR)/mapping.h $(SRCDIR)/mapping.c $(SRCDIR)/defs.h

$(BUILDDIR)/komplement.o: $(SRCDIR)/button_names.h $(SRCDIR)/komplement.c $(SRCDIR)/button_leds.h $(SRCDIR)/version.h $(SRCDIR)/defs.h $(SRCDIR)/alsa.h $(SRCDIR)/mmc_stuff.h

$(BUILDDIR)/button_names.o: $(SRCDIR)/button_names.c $(SRCDIR)/button_names.h $(SRCDIR)/defs.h 

$(BUILDDIR)/hid.o: $(SRCDIR)/hid.c $(SRCDIR)/hid.h

$(BUILDDIR)/hid_dump.o: $(SRCDIR)/hid_dump.c $(SRCDIR)/hid_dump.h

$(BUILDDIR)/button_leds.o: $(SRCDIR)/button_leds.c $(SRCDIR)/button_leds.h $(SRCDIR)/defs.h $(SRCDIR)/hid.h

$(BUILDDIR)/uinput_stuff.o: $(SRCDIR)/uinput_stuff.c $(SRCDIR)/uinput_stuff.h $(SRCDIR)/defs.h

# `komplementary` is the user space utility that translates
# HID events to keypresses.
komplement: $(KOMPLEMENT_OBJECTS)
	$(CC) -o komplement $(KOMPLEMENT_OBJECTS) $(LDFLAGS) $(KOMPLEMENT_LFLAGS)

# `konfigure` is a binary that creates SysEx to send to the
# device to configure the mappings.
$(BUILDDIR)/konfigure.o: $(SRCDIR)/konfigure.c $(SRCDIR)/konfigure.h $(SRCDIR)/konfigure_parser.h $(SRCDIR)/version.h

$(BUILDDIR)/konfigure_parser.o: $(SRCDIR)/konfigure_parser.c $(SRCDIR)/konfigure_parser.h

konfigure: $(KONFIGURE_OBJECTS)
	$(CC) -o konfigure $(KONFIGURE_OBJECTS) $(LDFLAGS) $(KONFIGURE_LFLAGS)
