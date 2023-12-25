// Directed testbench using Verilog 2001.
// This testbench is to make sense of the module's behaviour before conducting constraint random verification.
// Defines timescale for simulation: <time_unit> / <time_precision>
`timescale 1 ns / 10 ps

// Define our testbench
module testbench();

    // Simulation time: 10000 * 1 ns = 10 us
    localparam DURATION = 10000;

    // Parameters to pass to reg_ctrl
    parameter ADDR_WIDTH 	= 8;
    parameter DATA_WIDTH 	= 16;
    parameter DEPTH 		= 256;
    parameter RESET_VAL  	= 16'h1234;

    // 枚举值
    // 暂无

    // 寄存器（输入）
    reg 			 clk;
    reg 			 rstn;
    reg      [ADDR_WIDTH-1:0] addr;
    reg 			 sel;
    reg 			 wr;
    reg      [DATA_WIDTH-1:0] wdata;
 
    // 导线（输出）
    wire [DATA_WIDTH-1:0] rdata;
    wire		  ready;

    // 预期输出
    // 暂无

    // Instantiate the unit under test (UUT)
    reg_ctrl #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH), .RESET_VAL(RESET_VAL)
    ) uut (
        // 输入
        .clk(clk),
        .rstn(rstn),
        .addr(addr),
        .sel(sel),
        .wr(wr),
        .wdata(wdata),
        // 输出
        .rdata(rdata),
        .ready(ready)
    );

    // 验证输出值
    task check_ans();
	begin
            /*if (my_output != expected) begin
		$display("ERROR: output mismatch!");
		$display("expected: %b", expected);
		$display("got:      %b", my_output);
		$finish;
            end*/
	end
    endtask

    // 等到下一个时钟循环
    task next_cycle();
        begin
            clk = 0;
            #1;
            clk = 1;
            #1;
        end
    endtask

    // Toggle inputs and check output
    initial begin
        // Reset is active low.
        rstn = 0;
        // Hold reset for one clock cycle.
        next_cycle();

        // Disable reset.
        rstn = 1;
        // Read the default value from an address.
        addr = 0;
        sel = 1;
        wr = 0;
        next_cycle();

        // Try to write but at this point ready is low so the write is inaffective.
        wr = 1;
        wdata = 482;
        next_cycle();

        // Read the next cycle, at which we still read the default value.
        wr = 0;
        next_cycle();

        // Wait an extra cycle for ready to go high (needed after a read).
        next_cycle();

        // Now we try to write again when ready is true.
        wr = 1;
        next_cycle();

        // Read the next cycle, at which we now read the value we wanted to write (482).
        wr = 0;
        next_cycle();

        // Notify and end simulation
        $display("Finished!");
        $finish;
    end

    // Run simulation (output to .vcd file)
    initial begin
        // Create simulation output file
        $dumpfile("testbench.vcd");
        // 0 means look for variables in all levels
        $dumpvars(0, testbench);
        // Wait for given amount of time for simulation to complete
        // #(DURATION);
    end

endmodule
