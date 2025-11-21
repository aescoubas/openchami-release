.PHONY: all rpm srpm deb clean test-install

GIT     ?= $(shell command -v git 2>/dev/null)
TAG     ?= $(shell $(GIT) describe --tags --always --abbrev=0 2>/dev/null || echo v0.0.0)
VERSION ?= $(patsubst v%,%,$(TAG))
RELEASE ?= 1
HOME    ?= $(shell echo ${HOME})

# For recursive wildcard (used only by RPM source tarball)
rwildcard = $(foreach d,$(wildcard $(1:=/*)),$(call rwildcard,$d,$2) $(filter $(subst *,%,$2),$d))

# ------------------------------------------------------------------
# Default target – build RPM 
# ------------------------------------------------------------------
all: rpm

# ------------------------------------------------------------------
# RPM targets 
# ------------------------------------------------------------------
$(HOME)/rpmbuild:
	rpmdev-setuptree

$(HOME)/rpmbuild/SPECS/openchami.spec: openchami.spec | $(HOME)/rpmbuild
	mkdir -p $(HOME)/rpmbuild/SPECS
	cp $< $@

$(HOME)/rpmbuild/SOURCES/openchami-$(VERSION).tar.gz: | $(HOME)/rpmbuild $(call rwildcard,.,*)
	mkdir -p $(HOME)/rpmbuild/SOURCES
	rm -f $(HOME)/rpmbuild/SOURCES/openchami-$(VERSION).tar.gz
	tar czvf $@ --transform 's,^,openchami-$(VERSION)/,' \
		--exclude='$(HOME)/rpmbuild' \
		--exclude='debian' \
		--exclude='*.rpm' \
		--exclude='*.deb' \
		.

$(HOME)/rpmbuild/RPMS/noarch/openchami-$(VERSION)-$(RELEASE).noarch.rpm: \
		$(HOME)/rpmbuild/SPECS/openchami.spec \
		$(HOME)/rpmbuild/SOURCES/openchami-$(VERSION).tar.gz
	rpmbuild -ba $< \
		--define 'version $(VERSION)' \
		--define 'rel $(RELEASE)'

rpm: openchami-$(VERSION)-$(RELEASE).noarch.rpm
openchami-$(VERSION)-$(RELEASE).noarch.rpm: $(HOME)/rpmbuild/RPMS/noarch/openchami-$(VERSION)-$(RELEASE).noarch.rpm
	cp $< $@

srpm: $(HOME)/rpmbuild/SOURCES/openchami-$(VERSION).tar.gz $(HOME)/rpmbuild/SPECS/openchami.spec
	rpmbuild -bs $(HOME)/rpmbuild/SPECS/openchami.spec \
		--define 'version $(VERSION)' \
	\
		--define 'rel $(RELEASE)'

# ------------------------------------------------------------------
# DEB target 
# ------------------------------------------------------------------
deb:
	dpkg-buildpackage -us -uc -b
	mv ../openchami_*.deb ../openchami_*.changes ../openchami_*.buildinfo ./ 

# ------------------------------------------------------------------
# Shared install target 
# ------------------------------------------------------------------
PREFIX     ?= /usr
SYSCONFDIR ?= /etc
BINDIR     ?= $(PREFIX)/bin
LIBEXECDIR ?= $(PREFIX)/libexec
INSTALL    ?= install
DESTDIR    ?=

install:
	# Create directories
	install -d $(DESTDIR)/etc/openchami/configs
	install -d $(DESTDIR)/etc/openchami/pg-init
	install -d $(DESTDIR)/etc/containers/systemd
	install -d $(DESTDIR)/etc/systemd/system
	install -d $(DESTDIR)/usr/libexec/openchami
	install -d $(DESTDIR)/usr/bin
	install -d $(DESTDIR)/etc/profile.d

	# Files
	install -m 644 systemd/configs/*                              $(DESTDIR)/etc/openchami/configs/
	cp -r systemd/containers/* systemd/volumes/* systemd/networks/* $(DESTDIR)/etc/containers/systemd/
	cp -r systemd/targets/* systemd/system/*                      $(DESTDIR)/etc/systemd/system/

	# === Debian/Ubuntu certificate path fixes (only for .deb builds) ===
	if [ -n "$(DEB_BUILD_ARCH)" ] || [ -d "$(CURDIR)/debian" ]; then \
		set -e; \
		if [ -f $(DESTDIR)/etc/systemd/system/openchami-cert-trust.service ]; then \
			sed -i 's|/etc/pki/ca-trust/source/anchors/openchami\.pem|/usr/local/share/ca-certificates/openchami.crt|g' \
				$(DESTDIR)/etc/systemd/system/openchami-cert-trust.service; \
			sed -i '/^ExecStart=/c\ExecStart=/bin/sh -c "until podman cp step-ca:/root_ca/root_ca.crt /usr/local/share/ca-certificates/openchami.crt 2>/dev/null; do sleep 2; done && update-ca-certificates"' \
				$(DESTDIR)/etc/systemd/system/openchami-cert-trust.service; \
		fi; \
		find $(DESTDIR)/etc/containers/systemd -name '*.container' -type f -print0 | \
			xargs -0 sed -i 's|/etc/pki/ca-trust/extracted/pem/tls-ca-bundle\.pem|/etc/ssl/certs/ca-certificates.crt|g'; \
	fi

	# Scripts
	install -m 755 scripts/bootstrap_openchami.sh       $(DESTDIR)/usr/libexec/openchami/
	install -m 755 scripts/ohpc-nodes.sh                $(DESTDIR)/usr/libexec/openchami/
	install -m 755 scripts/openchami-certificate-update $(DESTDIR)/usr/bin/
	install -m 644 scripts/openchami_profile.sh         $(DESTDIR)/etc/profile.d/openchami.sh
	install -m 755 scripts/multi-psql-db.sh             $(DESTDIR)/etc/openchami/pg-init/

	# Permissions
	[ -f $(DESTDIR)/etc/openchami/configs/openchami.env ] && chmod 600 $(DESTDIR)/etc/openchami/configs/openchami.env || true
	chmod 644 $(DESTDIR)/etc/openchami/configs/*
	chmod +x $(DESTDIR)/usr/libexec/openchami/bootstrap_openchami.sh
	chmod +x $(DESTDIR)/usr/libexec/openchami/ohpc-nodes.sh
	chmod +x $(DESTDIR)/usr/bin/openchami-certificate-update

# ------------------------------------------------------------------
test-install:
	rm -rf _install_test
	$(MAKE) install DESTDIR=$(shell pwd)/_install_test
	@echo "Test installation completed in $(shell pwd)/_install_test"

# ------------------------------------------------------------------
# Clean
# ------------------------------------------------------------------
clean:
	rm -rf $(HOME)/rpmbuild
	rm -f openchami-*.noarch.rpm openchami_*.deb
	rm -rf debian/openchami debian/tmp debian/files debian/*.debhelper debian/*.substvars debian/*.log
