V=20261126

PREFIX = /usr/local

install:
	install -dm755 $(DESTDIR)$(PREFIX)/share/pacman/keyrings/
	install -m0644 sarchy{.gpg,-trusted} $(DESTDIR)$(PREFIX)/share/pacman/keyrings/

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/share/pacman/keyrings/sarchy{.gpg,-trusted}
	rmdir -p --ignore-fail-on-non-empty $(DESTDIR)$(PREFIX)/share/pacman/keyrings/

dist:
	git archive --format=tar --prefix=sarchy-keyring-$(V)/ $(V) | gzip -9 > sarchy-keyring-$(V).tar.gz
	gpg -u $(KEY) --detach-sign --use-agent sarchy-keyring-$(V).tar.gz

#.PHONY: install uninstall dist upload
.PHONY: install uninstall dist
