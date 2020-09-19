TARGET=libemu816.a

CPPFLAGS+=-O2 -I./

all:	$(TARGET)

clean:
	$(RM) *.o
	$(RM) $(TARGET)

$(TARGET):	emu816.o
	ar rcs $(TARGET)  emu816.o 

emu816.o: \
	emu816.cc emu816.h 

install: $(TARGET)
	cp $(TARGET) /usr/local/lib/
	cp emu816.h  /usr/local/include/
	
