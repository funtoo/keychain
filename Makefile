V=$(shell /bin/sh keychain.sh --version 2>&1 | \
	awk -F'[ ;]' '/^K/{print $$2; exit}')
D=$(shell date +'%d %b %Y')
TARBALL_CONTENTS=keychain README ChangeLog COPYING keychain.pod keychain.1 \
				 keychain.spec keychain-$V

all: keychain.1 keychain keychain.spec

keychain.spec: keychain.spec.in
	sed 's/KEYCHAIN_VERSION/$V/' keychain.spec.in > keychain.spec

keychain.1: keychain.pod Makefile
	pod2man --name=keychain --release=$V \
		--center='http://gentoo.org/proj/en/keychain.xml' \
		keychain.pod keychain.1

keychain: keychain.sh keychain.txt Makefile
	perl -e '\
		$$/ = undef; \
		open P, "keychain.txt" or die "cant open keychain.txt"; \
			$$_ = <P>; \
			s/^(NAME|SEE ALSO).*?\n\n//msg; \
			s/\$$/\\\$$/g; \
			s/\`/\\\`/g; \
			s/\*(\w+)\*/\$${CYAN}$$1\$${OFF}/g; \
			s/(^|\s)(-+[-\w]+)/$$1\$${GREEN}$$2\$${OFF}/mg; \
			$$pod = $$_; \
		open B, "keychain.sh" or die "cant open keychain.sh"; \
			$$_ = <B>; \
			s/INSERT_POD_OUTPUT_HERE\n/$$pod/ || die; \
		print' >keychain
	chmod +x keychain

keychain.txt: keychain.pod
	pod2text keychain.pod keychain.txt

keychain-$V.tar.gz: $(TARBALL_CONTENTS)
	@if ! grep -qF '* keychain $V ' ChangeLog; then \
		echo "**** Need to update the ChangeLog for version $V"; \
		exit 1; \
	fi
	@if ! grep -qF 'Keychain $V ' README; then \
		echo "**** Need to update the README for version $V"; \
		exit 1; \
	fi
	mkdir keychain-$V
	cp $(TARBALL_CONTENTS)
	sudo chown -R root:root keychain-$V
	/bin/tar cjvf keychain-$V.tar.bz2 keychain-$V
	sudo rm -rf keychain-$V
	ls -l keychain-$V.tar.bz2

# I believe that setting these NOTPARALLEL will result in them being
# built individually.  Hopefully GNU make will evaluate whether
# keychain-$V-1.src.rpm needs to be built after building
# keychain-$V-1.noarch.rpm so that rpmbuild isn't executed twice.
.NOTPARALLEL: keychain-$V-1.noarch.rpm keychain-$V-1.src.rpm
keychain-$V-1.noarch.rpm keychain-$V-1.src.rpm: keychain-$V.tar.gz
	rpmbuild -ta keychain-$V.tar.bz2
	rpm --addsign ~/redhat/RPMS/noarch/keychain-$V-1.noarch.rpm \
		~/redhat/SRPMS/keychain-$V-1.src.rpm

.PHONY: webpage
webpage:
	perl -0777i.bak -pe '\
		BEGIN{open F, "ChangeLog"; local $$/=undef; \
			($$C=<F>) =~ s/^.*?\n\n//s; \
			$$C =~ s/&/&amp;/g; \
			$$C =~ s/</&lt;/g; \
			$$C =~ s/>/&gt;/g; }; \
		s/(<version>).*?(?=<.version>)/$${1}$V/; \
		s/(<date>).*?(?=<.date>)/$${1}$D/; \
		s/(keychain-)[\d.]+(?=\.tar|\S*rpm)/$${1}$V/g; \
		s/(<!-- begin automatic ChangeLog insertion -->).*?(?=<!-- end)/$${1}$$C/s;' \
			~/gentoo/xml/htdocs/proj/en/keychain/index.xml
	cd ~/gentoo/xml/htdocs/proj/en/keychain && \
		cvs commit -m 'update to $V' index.xml

.PHONY: mypage
mypage: keychain-$V.tar.gz keychain-$V-1.noarch.rpm keychain-$V-1.src.rpm
	rsync -vPe ssh keychain-$V.tar.bz2 gentoo:public_html/keychain/
	rsync -vPe ssh ~/redhat/RPMS/noarch/keychain-$V-1.noarch.rpm \
		~/redhat/SRPMS/keychain-$V-1.src.rpm gentoo:public_html/keychain/
	ssh gentoo make -C public_html/keychain

.PHONY: release
release: mypage webpage

.PHONY: clean
clean:
	rm -f keychain keychain.txt keychain.1 keychain.spec
