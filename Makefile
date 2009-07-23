V:=$(shell /bin/sh keychain.sh --version 2>&1 | \
	awk -F'[ ;]' '/^K/{print $$2; exit}')
D:=$(shell date +'%d %b %Y')
TARBALL_CONTENTS=keychain README ChangeLog COPYING keychain.pod keychain.1 \
				 keychain.spec

all: keychain.1 keychain keychain.spec

keychain.spec: keychain.spec.in keychain.sh
	sed 's/KEYCHAIN_VERSION/$V/' keychain.spec.in > keychain.spec

keychain.1: keychain.pod keychain.sh
	pod2man --name=keychain --release=$V \
		--center='http://gentoo.org/proj/en/keychain.xml' \
		keychain.pod keychain.1
	sed -i "s/^'br/.br/" keychain.1

GENKEYCHAINPL = open P, "keychain.txt" or die "cant open keychain.txt"; \
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
		open B, "keychain.sh" or die "cant open keychain.sh"; \
			$$/ = undef; \
			$$_ = <B>; \
			s/INSERT_POD_OUTPUT_HERE\n/$$pod/ || die; \
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
	sudo chown -R root:root keychain-$V
	/bin/tar cjvf keychain-$V.tar.bz2 keychain-$V
	sudo rm -rf keychain-$V
	ls -l keychain-$V.tar.bz2

# Building noarch.rpm builds src.rpm at the same time.  I haven't
# found an elegant way yet to prevent parallel builds from messing
# this up, so all deps in the Makefile refer only to noarch.rpm
keychain-$V-1.noarch.rpm: keychain-$V.tar.gz
	rpmbuild -ta keychain-$V.tar.bz2
	mv ~/redhat/RPMS/noarch/keychain-$V-1.noarch.rpm \
		~/redhat/SRPMS/keychain-$V-1.src.rpm .
	rpm --addsign keychain-$V-1.noarch.rpm keychain-$V-1.src.rpm

GENWEBPAGEPL = BEGIN{open F, "ChangeLog"; local $$/=undef; \
			($$C=<F>) =~ s/^.*?\n\n//s; \
			$$C =~ s/&/&amp;/g; \
			$$C =~ s/</&lt;/g; \
			$$C =~ s/>/&gt;/g; }; \
		s/(<version>).*?(?=<.version>)/$${1}$V/; \
		s/(<date>).*?(?=<.date>)/$${1}$D/; \
		s/(keychain-)[\d.]+(?=\.tar|\S*rpm)/$${1}$V/g; \
		s/(<!-- begin automatic ChangeLog insertion -->).*?(?=<!-- end)/$${1}$$C/s
.PHONY: webpage
webpage:
	perl -0777i.bak -pe '$(GENWEBPAGEPL)' \
		~/g/gentoo/xml/htdocs/proj/en/keychain/index.xml
	cd ~/g/gentoo/xml/htdocs/proj/en/keychain && \
		cvs commit -m 'update to $V' index.xml

.PHONY: mypage
mypage: keychain-$V.tar.gz keychain-$V-1.noarch.rpm
	rsync -vPe ssh keychain-$V.tar.bz2 ChangeLog \
		keychain-$V-1.noarch.rpm keychain-$V-1.src.rpm \
		gentoo:public_html/keychain/
	ssh gentoo make -C public_html/keychain

.PHONY: release
release: mypage webpage
	rsync -vPe ssh keychain-$V.tar.bz2 gentoo:/space/distfiles-local/

.PHONY: clean
clean:
	rm -f keychain keychain.txt keychain.1 keychain.spec

.PHONY: test
test: keychain
	@./runtests
