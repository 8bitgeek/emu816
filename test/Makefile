
CPPFLAGS+=-O2 -I../src
LIBEMU816=../src/libemu816.a

all:	test0 test1 test2

clean:
	$(RM) *.o
	$(RM) test0
	$(RM) test1.o
	$(RM) test1.s
	$(RM) test1
	$(RM) test2.o
	$(RM) test2.s
	$(RM) test2


test0:	test0.o
	g++ test0.cc $(CPPFLAGS) $(LIBEMU816) -o test0

test1: test1.c
	cc65 -t sim65c02 test1.c
	ca65 -t sim65c02 test1.s
	cl65 -t sim65c02 test1.o

test2: test2.c
	cc65 -t sim65c02 test2.c
	ca65 -t sim65c02 test2.s
	cl65 -t sim65c02 test2.o

