V:=$(shell cat VERSION)
D:=$(shell date +'%d %b %Y')
RPMDIR=`rpmbuild -E '%_rpmdir'`
SRPMDIR=`rpmbuild -E '%_srcrpmdir'`
TARBALL_CONTENTS=keychain README.md ChangeLog COPYING.txt keychain.pod keychain.1 \
				 keychain.spec

all: keychain.1 keychain keychain.spec

.PHONY : tmpclean
tmpclean:
	rm -rf dist keychain.1.orig keychain.txt

.PHONY : clean
clean: tmpclean
	rm -rf keychain.1 keychain keychain.spec 

keychain.spec: keychain.spec.in keychain.sh
	sed 's/KEYCHAIN_VERSION/$V/' keychain.spec.in > keychain.spec

keychain.1: keychain.pod keychain.sh
	pod2man --name=keychain --release=$V \
		--center='http://www.funtoo.org' \
		keychain.pod keychain.1
	sed -i.orig -e "s/^'br/.br/" keychain.1

keychain.1.gz: keychain.1
	gzip -9 keychain.1

GENKEYCHAINPL = open P, "keychain.txt" or die "cannot open keychain.txt"; \
			while (<P>) { \
				$$printing = 0 if /^\w/; \
				$$printing = 1 if /^(SYNOPSIS|OPTIONS)/; \
				$$printing || next; \
				s/\$$/\\\$$/g; \
				s/\`/\\\`/g; \
				s/\\$$/\\\\/g; \
				s/\*(\w+)\*/\$${CYAN}$$1\$${OFF}/g; \
				s/(^|\s)(-+[-\w]+)/$$1\$${GREEN}$$2\$${OFF}/g; \
				$$pod .= $$_; \
			}; \
		open B, "keychain.sh" or die "cannot open keychain.sh"; \
			$$/ = undef; \
			$$_ = <B>; \
			s/INSERT_POD_OUTPUT_HERE[\r\n]/$$pod/ || die; \
			s/\#\#VERSION\#\#/$V/g || die; \
		print

keychain: keychain.sh keychain.txt
	perl -e '$(GENKEYCHAINPL)' >keychain || rm -f keychain
	chmod +x keychain

keychain.txt: keychain.pod
	pod2text keychain.pod keychain.txt

keychain-$V.tar.gz: $(TARBALL_CONTENTS)
	@case $V in *-test*) \
		echo "**** Version is $V, please remove -test"; \
		exit 1 ;; \
	esac
	@if ! grep -qF '* keychain $V ' ChangeLog; then \
		echo "**** Need to update the ChangeLog for version $V"; \
		exit 1; \
	fi
	mkdir keychain-$V
	cp $(TARBALL_CONTENTS) keychain-$V
	/bin/tar cjvf keychain-$V.tar.bz2 keychain-$V
	rm -rf keychain-$V
	ls -l keychain-$V.tar.bz2

# Building noarch.rpm builds src.rpm at the same time.  I haven't
# found an elegant way yet to prevent parallel builds from messing
# this up, so all deps in the Makefile refer only to noarch.rpm
keychain-$V-1.noarch.rpm-unsigned: keychain-$V.tar.gz
	rpmbuild -ta keychain-$V.tar.bz2
	mv $(RPMDIR)/noarch/keychain-$V-1.noarch.rpm \
		$(SRPMDIR)/keychain-$V-1.src.rpm .
keychain-$V-1.noarch.rpm: keychain-$V-1.noarch.rpm-unsigned
	rpm --addsign keychain-$V-1.noarch.rpm keychain-$V-1.src.rpm
