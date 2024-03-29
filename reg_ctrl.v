// 最新版本在Latitude（之后有可能在CAEN）
// Enable SystemVerilog support in Icarus Verilog with flag -g2005-sv. May need to use VCS.
// Note that in this protocol:
// - Write data is provided in a single clock along with the address.
// - Read data is received on the next clock, and no transactions can be started during that time indicated by "ready" signal.
//   i.e. no reads and writes can be initiated in the cycle following a read.

module reg_ctrl 
#(
     parameter ADDR_WIDTH 	= 8,
     parameter DATA_WIDTH 	= 16,
     parameter DEPTH 		= 256,
     parameter RESET_VAL  	= 16'h1234
)
(
     input 			 clk,
     input 			 rstn,
     input      [ADDR_WIDTH-1:0] addr,
     input 			 sel,
     input 			 wr,
     input      [DATA_WIDTH-1:0] wdata,
     output reg [DATA_WIDTH-1:0] rdata,
     output reg			 ready
);
  
    // Some memory element to store data for each addr
    reg [DATA_WIDTH-1:0] ctrl [DEPTH:0];
    reg  ready_dly;
    wire ready_pe;
    integer i; // Loop counter;

    // If reset is asserted, clear the memory element
    // Else store data to addr for valid writes
    // For reads, provide read data back
    always @(posedge clk) begin
        if (!rstn) begin
            for (i = 0; i < DEPTH; i = i+1) begin
                ctrl[i] <= RESET_VAL;
            end // for
        end else begin
    	    if (sel & ready & wr) begin
      		ctrl[addr] <= wdata;
    	    end // if
    	    if (sel & ready & !wr) begin
                rdata <= ctrl[addr];
  	    end else begin
                rdata <= 0;
            end // else
        end // else
    end // for
  
  // Ready is driven using this always block
  // During reset, drive ready as 1
  // Else drive ready low for a clock low
  // for a read until the data is given back
  always @(posedge clk) begin
      if (!rstn) begin
          ready <= 1;
      end else begin
          if (sel & ready_pe) begin
      	      ready <= 1;
          end
	  if (sel & ready & !wr) begin
              ready <= 0; // ready will be low on the next cycle.
          end
      end
  end
  
  // Drive internal signal accordingly
  always @ (posedge clk) begin
      if (!rstn) ready_dly <= 1;
      else ready_dly <= ready;
  end

  assign ready_pe = ~ready & ready_dly;

endmodule
