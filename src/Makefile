TARGET=libemu816.a

CPPFLAGS+=-O2 -I./

all:	$(TARGET)

clean:
	$(RM) *.o
	$(RM) $(TARGET)

$(TARGET):	wdc816.o emu816.o mem816.o
	ar rcs $(TARGET) wdc816.o emu816.o mem816.o

wdc816.o: \
	wdc816.cc wdc816.h

emu816.o: \
	emu816.cc emu816.h wdc816.h mem816.h

mem816.o: \
	mem816.cc mem816.h wdc816.h

