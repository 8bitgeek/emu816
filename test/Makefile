
CPPFLAGS+=-O2 -I./ -I../src -I../libs19
LIBEMU816=../src/libemu816.a
LIBS19=../libs19/libs19.a

all:	run816 test1 test2

clean:
	$(RM) *.o
	$(RM) *.lst
	$(RM) *.map
	$(RM) run816
	$(RM) test1.s
	$(RM) test1
	$(RM) test1.s19
	$(RM) test2.s
	$(RM) test2


run816:	run816.o
	g++ run816.cc vm816.cc load816.cc dbg816.cc trc816.cc $(CPPFLAGS) $(LIBS19) $(LIBEMU816) -o run816 -l ncurses

test1: test1.c
	cl65 -T --standard c99 -t sim65c02 -l test1.lst -m test1.map test1.c
	srec_cat test1 -binary -offset 0x200 -o test1.s19  -execution-start-address=0x200

test2: test2.c
	cc65 -t sim65c02 test2.c
	ca65 -t sim65c02 test2.s
	cl65 -t sim65c02 test2.o

