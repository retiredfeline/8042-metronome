#
# Uses GNU make for pattern substitution
#

%.bin:		%.hex
		hex2bin -e bin $<

metro.hex:	metro.asm table.asm
		as8048 -l -o $<
		aslink -i -o $(<:.asm=.rel)

table.asm:	gentab.py
		./gentab.py > table.asm

clean:
		rm -f *.sym *.lst *.rel *.hlr *.hex *.bin
