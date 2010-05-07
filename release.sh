#!/bin/bash

# This script is used by the keychain maintainer to generate new keychain releases.

PKG=keychain
VERSION=`cat VERSION`

versionsub() {
	# For keychain, this substitution stuff is done by the Makefile...
	cat $1 | sed -e "s/##VERSION##/$VERSION/g"
}

die() {
	echo $*
	exit 1
}

prep() {
	rm -rf dist/$PKG-$VERSION*
	install -d dist/$PKG-$VERSION
}

commit() {
	
	# Last step of a release is for the maintainer to update Changelog, README.rst and VERSIOn,
	# and then run "./release.sh all", which will run the following to make the release commit
	# and generate a release tarball. The release tarball is the current git tarball with "make"
	# run inside it, so that keychain, keychain.1 and keychain.spec are pre-generated for the
	# end-user. Since keychain is a script and the automated Makefile exists as a convenience
	# for the maintainer, we don't want to pass this complexity on to the consumers of this
	# package.

	#git commit -a -m "$VERSION distribution release" || die "commit failed"
	git archive --format=tar --prefix=${PKG}-${VERSION}/ HEAD | tar xf - -C dist || die "git archive fail"
	#git push || die "keychain git push failed"
	cd dist/$PKG-$VERSION || die "pkg cd fail"
	make clean all || die "make dist failed"
	cd .. || die "pkg cd .. fail"
	tar cjf $PKG-$VERSION.tar.bz2 $PKG-$VERSION || die "release tarball failed"
	cd .. || die "pkg cd .. again fail"
}

web() {
	cp dist/$PKG-$VERSION.tar.bz2 /root/git/website/archive/$PKG/ || die "web cp failed"
	cd /root/git/website || die "cd failed"
	#git add archive/$PKG/* || die "git add failed"
	#git commit -a -m "new $PKG $VERSION" || die "git commit failed"
	#git push || die "git push failed"
	./install.sh || die "web update failed"
}

if [ "$1" = "prep" ]
then
	prep
elif [ "$1" = "commit" ]
then
	commit
elif [ "$1" = "web" ]
then
	web
elif [ "$1" = "all" ]
then
	prep
	commit
	web
fi
