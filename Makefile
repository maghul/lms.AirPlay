NAME=AirPlay
VERSION=$(shell grep '<version>' install.xml | sed -e 's/.*<version>//'  -e 's%</version>%%' )
ZIP=$(NAME)_$(VERSION).zip

.PHONY: tests test tidy

tests:
	cd tests; make tests

test:
	cd tests; make test


build: ../$(ZIP) status
	echo "Building $(ZIP)"

clean:

status:
	git status

tidy:
	rm -f `find . -name '*.pm.bak'` `find . -name '*.pl.bak'`
	perltidy -i 8 -l 180 -b `find . -name '*.pm'` `find . -name '*.pl'`

../$(ZIP):
	cd ..; zip -rp $(ZIP) $(NAME)/*.pm $(NAME)/*.pl $(NAME)/HTML $(NAME)/install.xml $(NAME)/menu.opml $(NAME)/strings.txt $(NAME)/Bin/*

