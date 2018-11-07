#!/usr/bin/env python3

# The divisor required for the tick frequency for a given tempo
# is given by the formula:
#
# divisor = ticks in a minute / tempo
#
# If the tick period is 4 ms then there are 250 * 60 ticks in a minute

MODERATO = 112	# default tempo on boot

def tempoto4ms(tempo):
    return int(250.0 * 60.0 / tempo)


def printcount(tempo, count):
    print("\t.db\t%d\t; %d" % (count, tempo))


def printtempo(tempo):
    rem = tempo % 100
    hun = (tempo - rem) / 100
    print("\t.db\t0x%02d,0x%d" % (rem, hun))


def main():
    bcdtempi = []
    print("""\
tbot:		; count	; tempo\
""")
    for tempo in range(60, 80):
        printcount(tempo, tempoto4ms(tempo))
        bcdtempi.append(tempo)
    for tempo in range(80, 120):
        if tempo % 2 == 0:
            if tempo == MODERATO:
                print("defbpm:")
            printcount(tempo, tempoto4ms(tempo))
            bcdtempi.append(tempo)
    for tempo in range(120, 159):
        if tempo % 3 == 0:
            printcount(tempo, tempoto4ms(tempo))
            bcdtempi.append(tempo)
    for tempo in range(160, 240):
        if tempo % 4 == 0:
            printcount(tempo, tempoto4ms(tempo))
            bcdtempi.append(tempo)
    print("ttop:")
    print("""\
bcdtempi:
; table of bcdtempi in BCD for a display\
""")
    for tempo in bcdtempi:
        printtempo(tempo)


if __name__ == '__main__':
    main()
