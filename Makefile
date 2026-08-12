NAME := vidforge
VERSION := $(shell awk '$$1 == "Version:" { print $$2; exit }' packaging/vidforge.spec)
# rpmbuild's generated helper scripts do not consistently quote _topdir.
# Keep its working tree free of spaces, then copy the finished packages back.
TOPDIR ?= /tmp/$(NAME)-rpmbuild
OUTPUT_TOPDIR ?= $(CURDIR)/build/rpmbuild

.PHONY: rpm clean

rpm:
	mkdir -p "$(TOPDIR)/BUILD" "$(TOPDIR)/BUILDROOT" "$(TOPDIR)/RPMS" \
		"$(TOPDIR)/SOURCES" "$(TOPDIR)/SPECS" "$(TOPDIR)/SRPMS"
	git archive --format=tar.gz --prefix="$(NAME)-$(VERSION)/" \
		--output="$(TOPDIR)/SOURCES/$(NAME)-$(VERSION).tar.gz" HEAD
	cp packaging/vidforge.sysusers "$(TOPDIR)/SOURCES/"
	cp packaging/vidforge.spec "$(TOPDIR)/SPECS/"
	rpmbuild -ba --define "_topdir $(TOPDIR)" \
		"$(TOPDIR)/SPECS/vidforge.spec"
	mkdir -p "$(OUTPUT_TOPDIR)/RPMS" "$(OUTPUT_TOPDIR)/SRPMS"
	cp -a "$(TOPDIR)/RPMS/." "$(OUTPUT_TOPDIR)/RPMS/"
	cp -a "$(TOPDIR)/SRPMS/." "$(OUTPUT_TOPDIR)/SRPMS/"

clean:
	rm -rf "$(CURDIR)/build"
