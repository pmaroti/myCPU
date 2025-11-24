; Load immediate 0x42 into A
SET A, 0x42

; Write A to memory[pointer]
STA A

; Read back into B
LDA B

; Add B to A
ADD B

; If zero → jump to zeroHandler
JPZ zeroHandler

; Not A
NOT A

; Swap A with B
CHG B

zeroHandler:
SET A, 0x00
