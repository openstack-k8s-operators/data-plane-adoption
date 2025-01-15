BUILD ?= upstream
ABUILD_VARIANT ?=
BUILD_VARIANT_WITH_SEPARATOR ?= $(if $(strip $(BUILD_VARIANT)),-$(BUILD_VARIANT),)
BUILD_DIR = ../docs_build
ROOTDIR = $(realpath .)
NAME = adoption-user
DEST_DIR = $(BUILD_DIR)/$(NAME)
DEST_HTML = $(DEST_DIR)/index-$(BUILD)$(BUILD_VARIANT_WITH_SEPARATOR).html
DEST_PDF = $(BUILD_DIR)/$(NAME)-$(BUILD)$(BUILD_VARIANT_WITH_SEPARATOR).pdf
IMAGES_DIR = $(DEST_DIR)/images
IMAGES_TS = $(DEST_DIR)/.timestamp-images
MAIN_SOURCE = main.adoc
OTHER_SOURCES = $(shell find ./assemblies ./modules -type f)
IMAGES = $(shell find ./images -type f)
ALL_SOURCES = $(MAIN_SOURCE) $(OTHER_SOURCES) $(IMAGES)
UNAME = $(shell uname)
BUNDLE_EXEC ?= bundle exec

ifeq ($(UNAME), Linux)
BROWSER_OPEN = xdg-open
endif
ifeq ($(UNAME), Darwin)
BROWSER_OPEN = open
endif

all: html

html: html-latest

html-latest: prepare $(IMAGES_TS) $(DEST_HTML)

pdf: prepare $(DEST_PDF)

prepare:
	@if [ "$(BUILD)" != upstream -a "$(BUILD)" != downstream ]; then echo "BUILD must be 'upstream' or 'downstream'."; exit 1; fi
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(DEST_DIR) $(IMAGES_DIR)

clean:
	@rm -rf "$(DEST_DIR)" "$(DEST_PDF)"

watch-html:
	@which inotifywait > /dev/null || ( echo "ERROR: inotifywait not found, install inotify-tools" && exit 1 )
	while true; do \
		inotifywait -r -e modify -e create -e delete .; \
		sleep 0.5; \
		$(MAKE) html; \
	done

open-html: htmlf
	${BROWSER_OPEN} "file://$(realpath $(ROOTDIR)/$(DEST_HTML))"

open-pdf: pdf
	${BROWSER_OPEN} "$(realpath $(ROOTDIR)/$(DEST_PDF))"

$(IMAGES_TS): $(IMAGES)
	cp $? $(IMAGES_DIR)
	touch $(IMAGES_TS)

$(DEST_HTML): $(ALL_SOURCES)
	$(BUNDLE_EXEC) asciidoctor -a source-highlighter=highlightjs -a highlightjs-languages="yaml,bash" -a highlightjs-theme="monokai" --failure-level WARN -a build=$(BUILD) -a build_variant=$(BUILD_VARIANT) -b xhtml5 -d book -o $@ $(MAIN_SOURCE)

$(DEST_PDF): $(ALL_SOURCES)
	$(BUNDLE_EXEC) asciidoctor-pdf -a build=$(BUILD) -a build_variant=$(BUILD_VARIANT) -d book -o $@ $(MAIN_SOURCE) $(IMAGES)
