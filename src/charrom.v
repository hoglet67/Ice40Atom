module charrom ( output reg [7:0] dout, input[10:0] address, input clk);

   parameter MEM_INIT_FILE = "../mem/charrom.mem";

   reg [7:0] rom [0:2047];

   initial
     if (MEM_INIT_FILE != "")
       $readmemh(MEM_INIT_FILE, rom);
   
   always @(posedge clk)
     dout <= rom[address];

endmodule
