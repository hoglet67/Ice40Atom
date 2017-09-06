`timescale 1ns / 1ns

module atom_tb();

   parameter   CHARROM_INIT_FILE = "../mem/charrom.mem";
   parameter   VID_RAM_INIT_FILE = "../mem/vid_ram.mem";

   // This is used to simulate the ARM downloaded the initial set of ROM images
   parameter   BOOT_INIT_FILE    = "../mem/boot_c000_ffff.mem";
   parameter   BOOT_START_ADDR   = 'h0C000;
   parameter   BOOT_END_ADDR     = 'h0FFFF;

   reg [23:0]  boot_start = BOOT_START_ADDR;
   reg [23:0]  boot_end   = BOOT_END_ADDR;
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

   reg         arm_ss_r;
   reg         arm_sclk_r;
   reg         arm_mosi_r;

   reg         booting;

   wire        arm_ss;
   wire        arm_sclk;
   wire        arm_mosi;

   reg         ps2_clk;
   reg         ps2_data;
   reg         cas_in;

   integer     i, j, row, col;

   assign arm_ss   = booting ? arm_ss_r   : 1'bZ;
   assign arm_sclk = booting ? arm_sclk_r : 1'bZ;
   assign arm_mosi = booting ? arm_mosi_r : 1'bZ;

   // send a byte over SPI (MSB first)
   // data changes on falling edge of clock and is samples on rising edges
   task spi_send_byte;
      input [7:0] byte;
      for (j = 7; j >= 0; j = j - 1)
        begin
           #25 arm_sclk_r = 1'b0;
           arm_mosi_r = byte[j];
           #25 arm_sclk_r = 1'b1;
        end
   endtask

atom
  #(
    .CHARROM_INIT_FILE (CHARROM_INIT_FILE),
    .VID_RAM_INIT_FILE (VID_RAM_INIT_FILE)
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
      booting    = 1'b1;
      arm_ss_r   = 1'b1;
      arm_sclk_r = 1'b1;
      arm_mosi_r = 1'b1;
      // start the boot spi transfer by lowering ss
      #1000 arm_ss_r = 1'b0;
      // wait ~1us longer (as this is what the arm does)
      #1000;

      // send the ROM image start address
      spi_send_byte(boot_start[ 7: 0]);
      spi_send_byte(boot_start[15: 8]);
      spi_send_byte(boot_start[23:16]);
      // send the ROM image end address
      spi_send_byte(boot_end[ 7: 0]);
      spi_send_byte(boot_end[15: 8]);
      spi_send_byte(boot_end[23:16]);
      // send the ROM image data
      for (i = 0; i <= BOOT_END_ADDR - BOOT_START_ADDR; i = i + 1)
        spi_send_byte(boot[i]);

      #1000 arm_ss_r = 1'b1;
      #1000 booting  = 1'b0;

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

   always @(posedge DUT.clk25)
     if (DUT.cpu_clken && !DUT.reset)
       if (DUT.rnw)
         $display("Rd: %04x = %02x", DUT.address, DUT.cpu_din);
       else
         $display("Wr: %04x = %02x", DUT.address, DUT.cpu_dout);

   assign data_in = data;
   assign data = (!ramcs_b && !ramoe_b && ramwe_b) ? data_out : 8'hZZ;

   always @(posedge ramwe_b)
     if (ramcs_b == 1'b0)
       mem[addr] <= data_in;

   always @(addr)
     data_out <= mem[addr];

endmodule
