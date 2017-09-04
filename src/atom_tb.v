`timescale 1ns / 1ns

module opc6tb();

   parameter   CHARROM_INIT_FILE = "../mem/charrom.mem";
   parameter   VID_RAM_INIT_FILE = "../mem/vid_ram.mem";

   // This is used to simulate the ARM downloaded the initial set of ROM images
   parameter   BOOT_INIT_FILE    = "../mem/boot_c000_ffff.mem";

   parameter   BOOT_START_ADDR   = 'h0C000;
   parameter   BOOT_END_ADDR     = 'h0FFFF;

   reg [7:0]   boot [ 0 : BOOT_END_ADDR - BOOT_START_ADDR ];

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
   wire [3:0]  red;
   wire [3:0]  green;
   wire [3:0]  blue;
   wire        hsync;
   wire        vsync;

   wire        r_msb  = red[3];
   wire        g_msb  = green[3];
   wire        b_msb  = blue[3];

   reg         arm_ss;
   reg         arm_sclk;
   reg         arm_mosi;

   reg         ps2_clk;
   reg         ps2_data;
   reg         cas_in;

   integer     i, j, row, col;

atom
  #(
    .CHARROM_INIT_FILE (CHARROM_INIT_FILE),
    .VID_RAM_INIT_FILE (VID_RAM_INIT_FILE),
    .BOOT_START_ADDR(BOOT_START_ADDR),
    .BOOT_END_ADDR(BOOT_END_ADDR)
    )
   DUT
     (
      .clk100(clk),
      .sw4(reset_b),

      .arm_ss(arm_ss),
      .arm_sclk(arm_sclk),
      .arm_mosi(arm_mosi),

      .cas_in(cas_in),
      .ps2_clk(ps2_clk),
      .ps2_data(ps2_data),

      .miso(1'b1),

      .RAMWE_b(ramwe_b),
      .RAMOE_b(ramoe_b),
      .RAMCS_b(ramcs_b),
      .ADR(addr),
      .DAT(data),

      .red(red),
      .green(green),
      .blue(blue),
      .hsync(hsync),
      .vsync(vsync)
      );

   initial begin
      $dumpvars;
      // needed or the simulation hits an ambiguous branch
      mem[16'h00DE] = 8'h00;
      mem[16'h00DF] = 8'h00;
      mem[16'h00E0] = 8'h00;
      mem[16'h00E6] = 8'h00;

      // initialize 10MHz clock
      clk = 1'b0;
      // external reset should not be required, so don't simulate it
      reset_b  = 1'b1;
      // initialize other miscellaneous inputs
      cas_in <= 1'b0;
      ps2_clk <= 1'b1;
      ps2_data <= 1'b1;

      // load the boot image at 20MHz (should take 6ms for 16KB)
      $readmemh(BOOT_INIT_FILE, boot);
      arm_ss   = 1'b1;
      arm_sclk = 1'b1;
      arm_mosi = 1'b1;
      // start the boot spi transfer by lowering ss
      #1000 arm_ss = 1'b0;
      // wait ~1us longer (as this is what the arm does)
      #1000;
      // start sending the data (MSB first)
      // data changes on falling edge of clock and is samples on rising edges
      for (i = 0; i <= BOOT_END_ADDR - BOOT_START_ADDR; i = i + 1)
        for (j = 7; j >= 0; j = j - 1)
          begin
             #25 arm_sclk = 1'b0;
             arm_mosi = boot[i][j];
             #25 arm_sclk = 1'b1;
          end
      #1000 arm_ss = 1'b1;

      #100000000 ; // 100ms, enough for a few video frames

      // Attempt to dump the screen memory in ASCII
      for (row = 0; row < 16; row = row + 1)
        begin
           for (col = 0; col < 32; col = col + 1)
             begin
                i = 'h8000 + 32 * row + col;
                i = mem[i];
                i = i & 127;                
                if (i < 32)
                  i = i + 64;
                else if (i >= 64)
                  i = 'h2e;
                $write("%c", i);
             end
           $write("\n");
        end

      $finish;
           
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
