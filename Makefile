TARGET=dummy

$(TARGET):
	(cd libs19 && make)
	(cd src && make)
	(cd test && make)

clean:
	(cd libs19 && make clean)
	(cd src && make clean)
	(cd test && make clean)

