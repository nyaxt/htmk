CFLAGS+= -std=c99

check: htmk
	./htmk

htmk: htmk.c
	gcc $(CFLAGS) -o $@ $<

.PHONY: check
