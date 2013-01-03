LDFLAGS+= -g
CFLAGS+= -std=c99 -g

check: htmk
	./htmk

htmk: htmk.o scantest.o
	gcc $(LDFLAGS) -o $@ $^

htmk.o: htmk.c
	gcc $(CFLAGS) -c $<

scantest.o: scantest.nasm
	nasm -g -f elf64 -F dwarf $<

clean:
	rm *.o

.PHONY: check clean
