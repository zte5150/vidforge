NAME := av1-encoder
VERSION := 0.1.0
TOPDIR ?= $(CURDIR)/build/rpmbuild

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

clean:
	rm -rf "$(CURDIR)/build"
