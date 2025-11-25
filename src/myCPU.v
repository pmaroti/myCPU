module myCPU (
// ============================================================================
// myCPU.v   (Heavily commented / educational version)
// ----------------------------------------------------------------------------
// A minimalistic custom CPU with:
//
//   • 16 general-purpose 8-bit registers (pregs[0..15])
//   • 16-bit program counter (PCH:PCL)
//   • 8-bit instruction register (IR)
//   • 16-bit pointer register (POINTERH:POINTERL)
//   • simple fetch → decode → optional memory → execute micro-phases
//   • instructions encoded inside DI[2:0] (3-bit opcode)
//   • optional register index in DI[7:4]
//
// The CPU performs **one instruction fetch per two cycles**:
//
//   OP_FETCH1 → OP_FETCH2 → (optional memory phase) → OP_FETCH1...
//
// Memory interface:
//   AB  = 16-bit address bus
//   DI  = 8-bit data input from memory
//   DO  = 8-bit data output to memory
//   RW  = read(0) or write(1)
//
// This version includes EXCESSIVE comments for maximum clarity.
// ============================================================================ss
    // CPU clock and reset
    input  wire        CLK,      // rising-edge active clock
    input  wire        RESET,    // reset = initialize CPU

    // Memory interface
    input  wire [7:0]  DI,       // data read from memory
    output reg  [15:0] AB,       // address bus
    output reg  [7:0]  DO,       // data to memory (on write)
    output reg         RW        // READ=0, WRITE=1
);

// ============================================================================
// CPU MICRO-PHASE STATES
// These are *not* instructions — they are internal CPU pipeline microsteps.
// ============================================================================

parameter OP_FETCH1   = 8'h00;   // place PC on address bus, request memory read
parameter OP_FETCH2   = 8'h01;   // instruction arrives in DI → decode opcode
parameter OP_MEMREAD  = 8'h02;   // load register from memory
parameter OP_MEMWRITE = 8'h03;   // write register to memory

reg [2:0] phase;                 // current micro-phase

// ============================================================================
// CPU REGISTER FILE LAYOUT  (pregs[0..15])
// ============================================================================
// 16 8-bit registers. Index meanings:
//
//    0  = PCL        (program counter low byte)
//    1  = PCH        (program counter high byte)
//    2  = A          (accumulator)
//    3  = B
//    4  = C
//    5  = D
//    6  = POINTERL   (low byte of memory pointer)
//    7  = POINTERH   (high byte of memory pointer)
//    8  = STATUSL    (flags: Z, C, ...)
//    9  = STATUSH    (reserved)
//    A  = IR         (instruction register)
//    C  = JUMPL      (jump vector low)
//    D  = JUMPH      (jump vector high)
//    E  = E          (free)
//    F  = F          (free)
//
// Registers B–F are available to user code.
// ============================================================================

parameter regPCL       = 4'h0;
parameter regPCH       = 4'h1;
parameter regA         = 4'h2;
parameter regB         = 4'h3;
parameter regC         = 4'h4;
parameter regD         = 4'h5;
parameter regPOINTERL  = 4'h6;
parameter regPOINTERH  = 4'h7;
parameter regSTATUSL   = 4'h8;
parameter regSTATUSH   = 4'h9;
parameter regIR        = 4'hA;
parameter regJUMPL     = 4'hC;
parameter regJUMPH     = 4'hD;
parameter regE         = 4'hE;
parameter regF         = 4'hF;

// ============================================================================
// STATUS REGISTER BIT DEFINITIONS
// ---------------------------------------------------------------------------
// STATUSL bit 0 = Z  (Zero flag)
// STATUSL bit 1 = C  (Carry flag)
// ============================================================================

parameter statusRegZ   = 3'd0;
parameter statusRegC   = 3'd1;

// ============================================================================
// 16-entry register file
// ============================================================================

reg [7:0] pregs [0:15];      // 16 general-purpose registers

reg        carry;            // internal carry flag (not always used)
reg [8:0] sum9;
reg [7:0] tmp;
reg [3:0]  selectedReg;      // used for memory load target register

// ============================================================================
// Memory direction constants
// ============================================================================
parameter READ  = 1'b0;
parameter WRITE = 1'b1;

// ============================================================================
// OPCODE DEFINITIONS (3-bit opcode in DI[2:0])
// Leading upper nibble (DI[7:4]) often encodes a register index.
// ============================================================================

parameter INSTR_SET  = 3'h0;   // SET A = (next byte)
parameter INSTR_LD   = 3'h1;   // LDA: reg[DI[7:4]] = mem[pointer]
parameter INSTR_ST   = 3'h2;   // STA: mem[pointer] = reg[DI[7:4]]
parameter INSTR_AND  = 3'h3;   // A = A & R
parameter INSTR_ADD  = 3'h4;   // A = A + R (Z,C flags)
parameter INSTR_NOT  = 3'h5;   // R = ~R
parameter INSTR_JP   = 3'h6;   // if Z=1 then jump to {JUMPH,JUMPL}
parameter INSTR_CHG  = 3'h7;   // swap A ↔ R

integer i;

// ============================================================================
// MAIN CPU PROCESS
// Executes one micro-operation per clock.
// ============================================================================
always @(posedge CLK) begin

    // =========================================================================
    // RESET PHASE
    // =========================================================================
    if (RESET) begin
        // Clear all registers for deterministic startup
        
        pregs[0] <= 8'h00;
        pregs[1] <= 8'h00;
        pregs[2] <= 8'h00;
        pregs[3] <= 8'h00;
        pregs[4] <= 8'h00;
        pregs[5] <= 8'h00;
        pregs[6] <= 8'h00;
        pregs[8] <= 8'h00;
        pregs[9] <= 8'h00;
        pregs[10] <= 8'h00;
        pregs[11] <= 8'h00;
        pregs[12] <= 8'h00;
        pregs[13] <= 8'h00;
        pregs[14] <= 8'h00;
        pregs[15] <= 8'h00;


        // Start fetching from address 0x0000
        phase <= OP_FETCH1;

        // Initialize bus state
        AB    <= 16'h0000;
        DO    <= 8'h00;
        RW    <= READ;
        carry <= 1'b0;
        selectedReg <= 4'h0;
    end 
    else begin

        // =====================================================================
        // CPU MICRO-PHASE STATE MACHINE
        // =====================================================================
        case (phase)

        // =====================================================================
        // OP_FETCH1 — Place the PC on the address bus and request memory read
        // =====================================================================
        OP_FETCH1: begin
            AB <= {pregs[regPCH], pregs[regPCL]};  // address = PC
            RW <= READ;                            // request read
            phase <= OP_FETCH2;                    // next phase: fetch instruction
        end

        // =====================================================================
        // OP_FETCH2 — CPU receives instruction byte in DI
        // =====================================================================
        OP_FETCH2: begin
            pregs[regIR] <= DI;          // Store instruction byte into IR

            // Decode opcode (lower 3 bits)
            case (DI[2:0])

                // ---------------------------------------------------------------------
                // SET — Load immediate value into register A
                //   Format:    [ rrrr 0000 ]
                // ---------------------------------------------------------------------
                INSTR_SET: begin
                    selectedReg <= DI[7:4];    // load immediate selected reg
                    // Increase PC to next byte (the immediate)
                    {pregs[regPCH], pregs[regPCL]} <= 
                        {pregs[regPCH], pregs[regPCL]} + 16'd1;

                    // Memory read for the immediate byte
                    AB <= {pregs[regPCH], pregs[regPCL]} + 16'd1;
                    RW <= READ;
                    phase <= OP_MEMREAD;
                end

                // ---------------------------------------------------------------------
                // LDA — Load register from memory at pointer address
                // ---------------------------------------------------------------------
                INSTR_LD: begin
                    selectedReg <= DI[7:4];                // which register to load
                    AB <= {pregs[regPOINTERH], pregs[regPOINTERL]};
                    RW <= READ;
                    phase <= OP_MEMREAD;
                end

                // ---------------------------------------------------------------------
                // STA — Store register into memory at pointer address
                // ---------------------------------------------------------------------
                INSTR_ST: begin
                    AB <= {pregs[regPOINTERH], pregs[regPOINTERL]};
                    RW <= WRITE;
                    DO <= pregs[DI[7:4]];                  // write selected register
                    phase <= OP_MEMWRITE;
                end

                // ---------------------------------------------------------------------
                // AND — A = A & reg[R]
                // ---------------------------------------------------------------------
                INSTR_AND: begin
                    pregs[regA] <= pregs[regA] & pregs[DI[7:4]];
                    // Update Z flag
                    pregs[regSTATUSL][statusRegZ] <= 
                        ((pregs[regA] & pregs[DI[7:4]]) == 8'h00);
                    // Advance PC
                    {pregs[regPCH], pregs[regPCL]} <= 
                        {pregs[regPCH], pregs[regPCL]} + 16'd1;
                    phase <= OP_FETCH1;
                end

                // ---------------------------------------------------------------------
                // ADD — A = A + reg[R], update C,Z
                // ---------------------------------------------------------------------
                INSTR_ADD: begin
                    sum9 = {1'b0, pregs[regA]} + {1'b0, pregs[DI[7:4]]};
                    pregs[regA] <= sum9[7:0];
                    pregs[regSTATUSL][statusRegC] <= sum9[8];
                    pregs[regSTATUSL][statusRegZ] <= (sum9[7:0] == 8'h00);
                    {pregs[regPCH], pregs[regPCL]} <= 
                        {pregs[regPCH], pregs[regPCL]} + 16'd1;
                    phase <= OP_FETCH1;
                end

                // ---------------------------------------------------------------------
                // NOT — reg[R] = ~reg[R], update Z flag
                // ---------------------------------------------------------------------
                INSTR_NOT: begin
                    sum9[7:0] = ~pregs[DI[7:4]];
                    pregs[DI[7:4]] <= sum9[7:0];
                    pregs[regSTATUSL][statusRegZ] <= (sum9[7:0] == 8'h00);
                    {pregs[regPCH], pregs[regPCL]} <= 
                        {pregs[regPCH], pregs[regPCL]} + 16'd1;
                    phase <= OP_FETCH1;
                end
 
                // ------ ---------------------------------------------------------------
                // JPZ — Jump if status register bit is set/not set
                //    vbbb 0110 if status register bbb bit is v then branch
                // ---------------------------------------------------------------------
                INSTR_JP : begin
                    /*
                    if (pregs[regSTATUSL][statusRegZ]) begin
                        pregs[regPCL] <= pregs[regJUMPL];
                        pregs[regPCH] <= pregs[regJUMPH];
                    end
                    else begin
                        {pregs[regPCH], pregs[regPCL]} <= 
                            {pregs[regPCH], pregs[regPCL]} + 16'd1;
                    end
                    phase <= OP_FETCH1;
                    */
                    if (pregs[regSTATUSL][DI[6:4]] == DI[7]) begin
                        pregs[regPCL] <= pregs[regJUMPL];
                        pregs[regPCH] <= pregs[regJUMPH];
                    end
                    else begin
                        {pregs[regPCH], pregs[regPCL]} <= 
                            {pregs[regPCH], pregs[regPCL]} + 16'd1;
                    end
                    phase <= OP_FETCH1;                    
                    
                end

                // ---------------------------------------------------------------------
                // CHG — Swap A <-> reg[R]
                // ---------------------------------------------------------------------
                INSTR_CHG: begin
                    tmp = pregs[DI[7:4]];
                    pregs[DI[7:4]] <= pregs[regA];
                    pregs[regA] <= tmp;
                    {pregs[regPCH], pregs[regPCL]} <= 
                        {pregs[regPCH], pregs[regPCL]} + 16'd1;
                    phase <= OP_FETCH1;
                end

                // ---------------------------------------------------------------------
                // DEFAULT — Undefined opcode → treat as NOP
                // ---------------------------------------------------------------------
                default: begin
                    {pregs[regPCH], pregs[regPCL]} <= 
                        {pregs[regPCH], pregs[regPCL]} + 16'd1;
                    phase <= OP_FETCH1;
                end
            endcase
        end // OP_FETCH2

        // =====================================================================
        // OP_MEMREAD — Data from memory is in DI → store into selectedReg
        // =====================================================================
        OP_MEMREAD: begin
            pregs[selectedReg] <= DI;
            {pregs[regPCH], pregs[regPCL]} <= 
                {pregs[regPCH], pregs[regPCL]} + 16'd1;
            phase <= OP_FETCH1;
        end

        // =====================================================================
        // OP_MEMWRITE — Write was already issued; just advance PC
        // =====================================================================
        OP_MEMWRITE: begin
            {pregs[regPCH], pregs[regPCL]} <= 
                {pregs[regPCH], pregs[regPCL]} + 16'd1;
            phase <= OP_FETCH1;
        end

        // =====================================================================
        // Fallback
        // =====================================================================
        default: phase <= OP_FETCH1;

        endcase // phase
    end // not RESET
end // always


wire [0:7] r_regPCL = pregs[0];
wire [0:7] r_regPCH = pregs[1];
wire [0:7] r_regA = pregs[2];
wire [0:7] r_regB = pregs[3];
wire [0:7] r_regC = pregs[4];
wire [0:7] r_regD = pregs[5];
wire [0:7] r_regPOINTERL = pregs[6];
wire [0:7] r_regPOINTERH = pregs[7];
wire [0:7] r_regSTATUSL = pregs[8];
wire [0:7] r_regSTATUSH = pregs[9];
wire [0:7] r_regIR = pregs[10];
wire [0:7] r_regJUMPL = pregs[12];
wire [0:7] r_regJUMPH = pregs[13];
wire [0:7] r_regE = pregs[14];
wire [0:7] r_regF = pregs[15];


endmodule