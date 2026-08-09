NAME := av1-encoder
VERSION := 0.1.0
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
	cp packaging/av1-encoder.sysusers "$(TOPDIR)/SOURCES/"
	cp packaging/av1-encoder.spec "$(TOPDIR)/SPECS/"
	rpmbuild -ba --define "_topdir $(TOPDIR)" \
		"$(TOPDIR)/SPECS/av1-encoder.spec"
	mkdir -p "$(OUTPUT_TOPDIR)/RPMS" "$(OUTPUT_TOPDIR)/SRPMS"
	cp -a "$(TOPDIR)/RPMS/." "$(OUTPUT_TOPDIR)/RPMS/"
	cp -a "$(TOPDIR)/SRPMS/." "$(OUTPUT_TOPDIR)/SRPMS/"

clean:
	rm -rf "$(CURDIR)/build"
