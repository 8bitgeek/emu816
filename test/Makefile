
CPPFLAGS+=-O2 -I./ -I../src -DDEBUG
LIBEMU816=../src/libemu816.a

all:	run816 test1 test2

clean:
	$(RM) *.o
	$(RM) run816
	$(RM) test1.s
	$(RM) test1
	$(RM) test2.s
	$(RM) test2


run816:	run816.o
	g++ run816.cc vm816.cc dbg816.cc $(CPPFLAGS) $(LIBEMU816) -o run816

test1: test1.c
	cc65 -t sim65c02 test1.c
	ca65 -t sim65c02 test1.s
	cl65 -t sim65c02 test1.o

test2: test2.c
	cc65 -t sim65c02 test2.c
	ca65 -t sim65c02 test2.s
	cl65 -t sim65c02 test2.o

