LDFLAGS+= -g -ldl
CFLAGS+= -std=c99 -g

check: htmk scantest.so
	./htmk

htmk: htmk.o
	gcc $(LDFLAGS) -o $@ $^

htmk.o: htmk.c
	gcc $(CFLAGS) -c $<

scantest.so: scantest.o
	ld -shared -o $@ $<

scantest.o: scantest.nasm
	nasm -g -f elf64 -F dwarf $<

clean:
	rm *.o *.so

.PHONY: check clean
