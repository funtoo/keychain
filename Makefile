V=$(shell /bin/sh keychain.sh --version 2>&1 | \
	awk -F'[ ;]' '/^K/{print $$2; exit}')

all: keychain.1 keychain

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

clean:
	rm -f keychain keychain.txt keychain.1

tarball: all
	if [ `id -u` != 0 ]; then \
		echo "You must be root to create the tarball" >&2; \
		exit 1; \
	fi
	mkdir keychain-$V
	cp keychain README ChangeLog COPYING keychain.pod keychain.1 \
		keychain.spec keychain-$V
	chown -R root:root keychain-$V
	/bin/tar cjvf keychain-$V.tar.bz2 keychain-$V
	rm -rf keychain-$V
	ls -l keychain-$V.tar.bz2
