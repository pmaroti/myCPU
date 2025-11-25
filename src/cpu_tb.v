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
    // INITIALIZATION & TEST CONTROL
    // =========================================================================
    initial begin
        $display("===== CPU TEST START =====");
        $dumpfile("cpu_test.vcd");
        $dumpvars(0, cpu_tb);

        $readmemh("counter.hex", MEM);

        // Hold reset for 5 cycles
        repeat (5) @(posedge CLK);
        RESET = 0;

        // Run simulation for 5000ns
        repeat (500) @(posedge CLK);


        $display("===== CPU TEST FINISHED =====");
        $finish;
    end

endmodule
