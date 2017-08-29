`timescale 1ns / 1ns
module opc6tb
  #(
    parameter charrom_init_file = "../mem/charrom.mem",
    parameter vid_ram_init_file = "../mem/vid_ram.mem"
    );
   reg [17:0]  mem [ 0:262143 ];
   
   reg         clk;
   reg         reset_b;
   wire [17:0] addr;
   wire [7:0]  data;
   wire [7:0]  data_in;
   reg [7:0]   data_out;
   wire        ramwe_b;
   wire        ramoe_b;
   wire        ramcs_b;
   wire [2:0]  r;
   wire [2:0]  g;
   wire [1:0]  b;
   wire        hsync;
   wire        vsync;
   
   wire        r_msb  = r[2];
   wire        g_msb  = g[2];
   wire        b_msb  = b[1];
   
atom
  #(
    .charrom_init_file (charrom_init_file),
    .vid_ram_init_file (vid_ram_init_file)
    )
   DUT (
          .clk100(clk),
          .sw4(reset_b),

          .RAMWE_b(ramwe_b),
          .RAMOE_b(ramoe_b),
          .RAMCS_b(ramcs_b),
          .ADR(addr),
          .DAT(data),

          .r(r),
          .g(g),
          .b(b),
          .hsync(hsync),
          .vsync(vsync)
          );

   initial begin
      // needed or the simulation hits an ambiguous branch
      mem[16'h00DE] = 8'h00;
      mem[16'h00DF] = 8'h00;
      mem[16'h00E0] = 8'h00;
      mem[16'h00E6] = 8'h00;
      
      $dumpvars;
      clk = 0;
      reset_b = 1;
      #1002 reset_b = 0;
      #5002 reset_b = 1;
      #50000000 $finish; // 50ms, enough for a few video frames
   end
   
   always
     #5 clk = !clk;

   assign data_in = data;
   assign data = (!ramcs_b && !ramoe_b && ramwe_b) ? data_out : 8'hZZ;
   
  
   always @(posedge ramwe_b)
     if (ramcs_b == 1'b0)
       mem[addr] <= data_in;
           
   always @(addr)
     data_out <= mem[addr];
   
endmodule
