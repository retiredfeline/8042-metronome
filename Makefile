#
# Uses GNU make for pattern substitution
#
# The primary target will use both assemblers and compare the results
# but if you just use one assembler change the target to
# metro.bin, metro.ihx or metro.ibn
#

default:	compare

compare:	metro.bin metro.ibn metro.zbn
		cmp metro.bin metro.zbn

%.zbn:		%.ihx
		hex2bin -e zbn -p 00 $<

%.ibn:		%.ihx
		hex2bin -e ibn $<

metro.bin:	metro.asm table.asm
		asm48 -t -s $(<:.asm=.sym) $<

metro.hex:	metro.asm table.asm
		asm48 -f hex $<

metro.ihx:	metro.asm table.asm
		as8048 -l -o $<
		aslink -i -o $(<:.asm=.rel)

table.asm:	gentab.py
		./gentab.py > table.asm

clean:
		rm -f *.sym *.lst *.rel *.hlr *.bin *.ihx *.ibn *.zbn
