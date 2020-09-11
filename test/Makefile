
CPPFLAGS+=-O2 -I../src
LIBEMU816=../src/libemu816.a

all:	emu816

clean:
	$(RM) *.o
	$(RM) emu816

emu816:	program.o
	g++ program.o $(LIBEMU816) -o emu816

program.o: \
	program.cc $(LIBEMU816)

