        SET POINTERL, 0x00
        SET POINTERH, 0x20

        SET JUMPH, back, H
        SET JUMPL, back, L

        SET B, 0x01
        SET A, 0x00

back: 
        ST  A
        ADD B
        AND A
        SET STATUSL, 0x00
        JP  0, 0