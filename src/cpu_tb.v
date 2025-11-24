`define SIM 1
`include "myCPU.v"

module cpu_tb();

    // -------------------------------------------------------------------------
    // CLOCK AND RESET
    // -------------------------------------------------------------------------
    reg CLK = 0;
    reg RESET = 1;

    //always #5 CLK = ~CLK;   // 100MHz clock (10ns period)
    always #2 CLK = ~CLK;   // 500MHz clock (2ns period)

    // -------------------------------------------------------------------------
    // CPU I/O WIRES
    // -------------------------------------------------------------------------
    wire [15:0] AB;
    wire  [7:0] DO;
    wire  [7:0] DI;
    wire        RW;

    // -------------------------------------------------------------------------
    // Instantiate your CPU
    // -------------------------------------------------------------------------
    myCPU uut (
        .CLK(CLK),
        .RESET(RESET),
        .DI(DI),
        .AB(AB),
        .DO(DO),
        .RW(RW)
    );

    // -------------------------------------------------------------------------
    // Simple test RAM (64KB)
    // In your CPU, reads happen with RW = 0 and writes with RW = 1
    // -------------------------------------------------------------------------
    reg [7:0] MEM [0:65535];

    assign DI = (RW == 0) ? MEM[AB] : 8'hZZ;

    integer i;    

    always @(posedge CLK) begin
        if (RW == 1) begin
            MEM[AB] <= DO;
        end
    end

    // =========================================================================
    // TEST PROGRAM LOADED INTO MEMORY
    //
    // It will:
    //   1. SET A = 0x55
    //   2. LDA B from pointer (pointer set to 0x2000 → contains 0xAA)
    //   3. STA B back to 0x2001
    //   4. AND A with B    (0x55 & 0xAA = 0x00 → zero flag = 1)
    //   5. ADD A with B    (0 + 0xAA = 0xAA)
    //   6. NOT B           ( ~0xAA = 0x55 )
    //   7. JPZ to jumpVector (should not jump now)
    //   8. CHG A ↔ B       (swap)
    //
    // The expected final values are included below.
    // =========================================================================

    task load_program;
    begin

        // Clear memory
        for (i = 0; i < 65536; i = i + 1)
            MEM[i] = 8'h00;

        // --- Write test values in memory ---
        MEM[16'h2000] = 8'hAA;    // value for LDA
        MEM[16'h2001] = 8'h00;    // for STA test

        // ---------------------------------------------------------------------
        // PROGRAM START AT 0x0000
        // ---------------------------------------------------------------------

        //  SET A ← immediate
        MEM[16'h0000] = 8'b0000_0000;  // SET opcode
        MEM[16'h0001] = 8'h00;         // immediate value

        //  CHG A ↔ POINTERL
        MEM[16'h0002] = 8'b0110_0111;  // CHG, R=POINTERL       

        //  SET A ← immediate
        MEM[16'h0003] = 8'b0000_0000;  // SET opcode
        MEM[16'h0004] = 8'h20;         // immediate value

        //  CHG A ↔ POINTERH
        MEM[16'h0005] = 8'b0111_0111;  // CHG, R=POINTERH       

        //  SET A ← immediate
        MEM[16'h0006] = 8'b0000_0000;  // SET opcode
        MEM[16'h0007] = 8'h55;         // immediate value        


        //  LDA B
        MEM[16'h0008] = 8'b0011_0001;  // LDA, register index=3 (B)

        //  STA B
        MEM[16'h0009] = 8'b0011_0010;  // STA, register index=3

        //  AND A with B
        MEM[16'h000A] = 8'b0011_0011;  // AND, R=B

        //  ADD A with B
        MEM[16'h000B] = 8'b0011_0100;  // ADD, R=B

        //  NOT B
        MEM[16'h000C] = 8'b0011_0101;  // NOT, R=B

        //  JPZ
        MEM[16'h000D] = 8'b0000_0110;  // JPZ instruction

        //  CHG A ↔ B
        MEM[16'h000E] = 8'b0011_0111;  // CHG, R=B
    end
    endtask

    // =========================================================================
    // INITIALIZATION & TEST CONTROL
    // =========================================================================
    initial begin
        $display("===== CPU TEST START =====");
        $dumpfile("cpu_test.vcd");
        $dumpvars(0, cpu_tb);

        load_program();

        // Hold reset for 5 cycles
        repeat (5) @(posedge CLK);
        RESET = 0;

        // Run simulation for 5000ns
        repeat (500) @(posedge CLK);

        check_results();

        $display("===== CPU TEST FINISHED =====");
        $finish;
    end

    // =========================================================================
    // CHECK RESULTS
    // =========================================================================

    task expect(input [7:0] val, input [7:0] exp, input [127:0] name);
    begin
        if (val !== exp)
            $display("FAIL: %s expected %h got %h", name, exp, val);
        else
            $display("PASS: %s = %h", name, val);
    end
    endtask

    task check_results;
    begin
        $display("\n===== CHECKING CPU RESULTS =====");

        // Word-by-word checking

        expect(uut.pregs[uut.regA], 8'h55, "NOT swapped A? (final A after swap)");  
        expect(uut.pregs[uut.regB], 8'hAA, "Final B after CHG swap");               
        expect(MEM[16'h2001],      8'hAA, "STA wrote B to memory location 0x2001");

        expect(uut.pregs[uut.regSTATUSL][uut.statusRegZ], 1'b0, "Final Z flag");
        expect(uut.pregs[uut.regSTATUSL][uut.statusRegC], 1'b0, "Final C flag");
    end
    endtask

endmodule
