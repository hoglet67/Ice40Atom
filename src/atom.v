// =======================================================================
// Ice40Atom
//
// An Acorn Atom implementation for the Ice40
//
// Copyright (C) 2017 David Banks
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see http://www.gnu.org/licenses/.
// =======================================================================

// The IceStorm sythesis scripts defines use_sb_io to force
// the instantaion of SB_IO (as inferrence broken)
// `define use_sb_io

module atom
   (
             // Main clock, 100MHz
             input         clk100,
             // ARM SPI slave, to bootstrap load the ROMS
             input         arm_ss,
             input         arm_sclk,
             input         arm_mosi,
             output        arm_miso,
             // SD Card SPI master
             output        ss,
             output        sclk,
             output        mosi,
             input         miso,
             // Test outputs
             output        test0,
             output        test1,
             output        test2,
             output        test3,
             // LEDs
             //output        led1,
             //output        led2,
             //output        led3,
             //output        led4,
             // Switches
             //input         sw1_1,
             //input         sw1_2,
             //input         sw2_1,
             //input         sw2_2,
             //input         sw3,
             input         sw4,
             // External RAM
             output        RAMWE_b,
             output        RAMOE_b,
             output        RAMCS_b,
             output [17:0] ADR,
             inout [7:0]   DAT,
             // Cassette / Sound
             input         cas_in,
             output        cas_out,
             output        sound,
             // Keyboard
             input         ps2_clk,
             input         ps2_data,
             // Video
             output [3:0]  red,
             output [3:0]  green,
             output [3:0]  blue,
             output        hsync,
             output        vsync
             );

   // ===============================================================
   // Parameters
   // ===============================================================

   parameter CHARROM_INIT_FILE = "../mem/charrom.mem";
   parameter VID_RAM_INIT_FILE = "../mem/vid_ram.mem";
   parameter BOOT_START_ADDR   = 'h0C000;
   parameter BOOT_END_ADDR     = 'h0FFFF;

   // ===============================================================
   // Wires/Reg definitions
   // TODO: reorganize so all defined here
   // ===============================================================

   reg         hard_reset_n;
   wire        booting;
   wire        break_n;
   reg [7:0]   pia_pa_r = 8'b00000000;
   reg         rnw;
   wire [7:0]  pia_pc;
   wire        pia_cs;
   wire        wemask;
   reg [15:0]  address;
   reg [7:0]   cpu_dout;
   wire [7:0]  vid_dout;
   wire [7:0]  spi_dout;
   wire [7:0]  via_dout;
   wire        via_irq_n;

   // ===============================================================
   // System Clock generation (25MHz)
   // ===============================================================

   reg [1:0]  clkpre = 2'b00;     // prescaler, from 100MHz to 25MHz

   always @(posedge clk100)
     begin
        clkpre <= clkpre + 1;
     end
   wire clk25 = clkpre[1];

   // ===============================================================
   // VGA Clock generation (25MHz/12.5MHz)
   // ===============================================================

   wire clk_vga = clk25;
   reg  clk_vga_en = 0;

   always @(posedge clk_vga)
     clk_vga_en <= !clk_vga_en;

   // ===============================================================
   // Clock Enable Generation
   // ===============================================================

   reg       cpu_clken;
   reg       via1_clken;
   reg       via4_clken;
   reg       wegate_b;
   reg [4:0] clkdiv = 5'b00000;  // divider, from 25MHz down to 1MHz

   always @(posedge clk25) begin
     if (clkdiv == 24)
       clkdiv <= 0;
     else
       clkdiv <= clkdiv + 1;
     cpu_clken  <= (clkdiv == 24);
     via1_clken <= (clkdiv == 24);
     via4_clken <= (clkdiv == 6) | (clkdiv == 12) | (clkdiv == 18) || (clkdiv == 24);
      // It's pretty arbitrary when in the cycle the write actually happens
     wegate_b <= (clkdiv != 0);
   end

   // ===============================================================
   // Reset generation
   // ===============================================================

   reg [9:0] pwr_up_reset_counter = 0; // hold reset low for ~1ms
   wire      pwr_up_reset_n = &pwr_up_reset_counter;

   always @(posedge clk25)
     begin
        if (cpu_clken)
          begin
             if (!pwr_up_reset_n)
               pwr_up_reset_counter <= pwr_up_reset_counter + 1;
             hard_reset_n <= sw4 & pwr_up_reset_n;
          end
     end

   wire reset = !hard_reset_n | !break_n | booting;

   // ===============================================================
   // LEDs
   // ===============================================================

   //assign led1 = reset;    // blue
   //assign led2 = 1'b1;     // green
   //assign led3 = 1'b0;     // yellow
   //assign led4 = 1'b0;     // red

   // ===============================================================
   // Keyboard
   // ===============================================================

   wire rept_n;
   wire shift_n;
   wire ctrl_n;
   wire [3:0] row = pia_pa_r[3:0];
   wire [5:0] keyout;

   keyboard KBD
     (
      .CLK(clk25),
      .nRESET(hard_reset_n),
      .PS2_CLK(ps2_clk),
      .PS2_DATA(ps2_data),
      .KEYOUT(keyout),
      .ROW(row),
      .SHIFT_OUT(shift_n),
      .CTRL_OUT(ctrl_n),
      .REPEAT_OUT(rept_n),
      .BREAK_OUT(break_n)
      );

   // ===============================================================
   // Cassette
   // ===============================================================

   // The Atom drives cas_tone from 4MHz / 16 / 13 / 8
   // 208 = 16 * 13, and start with 1MHz and toggle
   // so it's basically the same

   reg        cas_tone = 1'b0;
   reg [7:0]  cas_div = 0;

   always @(posedge clk25)
     if (cpu_clken)
       begin
          if (cas_div == 207)
            begin
               cas_div <= 0;
               cas_tone <= !cas_tone;
            end
          else
            cas_div <= cas_div + 1;
       end

   assign sound = pia_pc[2];

   // this is a direct translation of the logic in the atom
   // (two NAND gates and an inverter)
   assign cas_out = !(!(!cas_tone & pia_pc[1]) & pia_pc[0]);

   // ===============================================================
   // Bootstrap (of ROM content from ARM into RAM )
   // ===============================================================


   wire        atom_RAMCS_b = 1'b0;
   wire        atom_RAMOE_b = !rnw;
   wire        atom_RAMWE_b = rnw  | wegate_b | wemask;
   wire [17:0] atom_RAMA    = { 2'b00, address };
   wire [7:0]  atom_RAMDin  = cpu_dout;

   wire        ext_RAMCS_b;
   wire        ext_RAMOE_b;
   wire        ext_RAMWE_b;
   wire [17:0] ext_RAMA;
   wire [7:0]  ext_RAMDin;

   wire        progress;

   bootstrap
     #(
       .BOOT_START_ADDR(BOOT_START_ADDR),
       .BOOT_END_ADDR(BOOT_END_ADDR)
       )
   BS
     (
      .clk(clk100),
      .booting(booting),
      .progress(progress),
      // SPI Slave Interface (runs at 20MHz)
      .SCK(arm_sclk),
      .SSEL(arm_ss),
      .MOSI(arm_mosi),
      .MISO(arm_miso),
      // RAM from Atom
      .atom_RAMCS_b(atom_RAMCS_b),
      .atom_RAMOE_b(atom_RAMOE_b),
      .atom_RAMWE_b(atom_RAMWE_b),
      .atom_RAMA(atom_RAMA),
      .atom_RAMDin(atom_RAMDin),
      // RAM to external SRAM
      .ext_RAMCS_b(ext_RAMCS_b),
      .ext_RAMOE_b(ext_RAMOE_b),
      .ext_RAMWE_b(ext_RAMWE_b),
      .ext_RAMA(ext_RAMA),
      .ext_RAMDin(ext_RAMDin)
   );

   assign test0 = arm_ss;
   assign test1 = arm_sclk;
   assign test2 = arm_mosi;
   assign test3 = progress;

   // ===============================================================
   // External RAM
   // ===============================================================

   assign RAMCS_b = ext_RAMCS_b;
   assign RAMOE_b = ext_RAMOE_b;
   assign RAMWE_b = ext_RAMWE_b;
   assign ADR     = ext_RAMA;

`ifdef use_sb_io
   // IceStorm cannot infer bidirectional I/Os
   wire [7:0] data_pins_in;
   wire [7:0] data_pins_out = ext_RAMDin;
   wire       data_pins_out_en = !ext_RAMWE_b;
   SB_IO #(
           .PIN_TYPE(6'b 1010_01)
           ) sram_data_pins [7:0] (
                                   .PACKAGE_PIN(DAT),
                                   .OUTPUT_ENABLE(data_pins_out_en),
                                   .D_OUT_0(data_pins_out),
                                   .D_IN_0(data_pins_in)
                                   );
`else
   assign DAT = (ext_RAMWE_b) ? 8'bz : ext_RAMDin;
   wire [7:0] data_pins_in = DAT;
`endif

   // ===============================================================
   // 8255 PIA at 0xB0xx
   // ===============================================================

   // This model is still very crude, specifically the directions of
   // the ports are fixed (not normally a problem on the Atom)

   wire        fs_n;
   reg [7:0]  pia_dout;
   reg [3:0]  pia_pc_r = 4'b0000;
   wire [7:0] pia_pa   = { pia_pa_r };
   wire [7:0] pia_pb   = { shift_n, ctrl_n, keyout };
   assign pia_pc   = { fs_n, rept_n, cas_in, cas_tone, pia_pc_r};

   always @(posedge clk25)
     begin
        if (cpu_clken)
          begin
             if (pia_cs && !rnw)
               case (address[1:0])
                 2'b00: pia_pa_r <= cpu_dout;
                 2'b10: pia_pc_r <= cpu_dout[3:0];
                 2'b11: if (!cpu_dout[7]) pia_pc_r[cpu_dout[2:1]] <= cpu_dout[0];
               endcase
          end
     end

   always @(*)
     begin
        case(address[1:0])
          2'b00: pia_dout <= pia_pa;
          2'b01: pia_dout <= pia_pb;
          2'b10: pia_dout <= pia_pc;
          default:
            pia_dout <= 0;
        endcase
     end


   // ===============================================================
   // 6502 CPU
   // ===============================================================

   wire  [7:0] cpu_din;
   wire [7:0]  cpu_dout_c;
   wire [15:0] address_c;
   wire        rnw_c;

   // Arlet's 6502 core is one of the smallest available
   cpu CPU
     (
      .clk(clk25),
      .reset(reset),
      .AB(address_c),
      .DI(cpu_din),
      .DO(cpu_dout_c),
      .WE(rnw_c),
      .IRQ(!via_irq_n),
      .NMI(1'b0),
      .RDY(cpu_clken)
      );

   // The outputs of Arlets's 6502 core need registing
   always @(posedge clk25)
     begin
        if (cpu_clken)
          begin
             address  <= address_c;
             cpu_dout <= cpu_dout_c;
             rnw      <= !rnw_c;
          end
     end


   // ===============================================================
   // Address decoding logic and data in multiplexor
   // ===============================================================

   wire [7:0]  pl8_dout = 8'b0;

   wire        rom_cs = (address[15:14] == 2'b11);
   assign      pia_cs = (address[15:10] == 6'b101100);
   wire        pl8_cs = (address[15:10] == 6'b101101);
   wire        via_cs = (address[15:10] == 6'b101110);
   wire        spi_cs = (address[15:8]  == 8'b10111100);
   wire        ram_cs = (address[15]    == 1'b0) | rom_cs;
   wire        vid_cs = (address[15:13] == 3'b100);

   assign      wemask = rom_cs;

   assign cpu_din = ram_cs   ? data_pins_in :
                    vid_cs   ? vid_dout :
                    pia_cs   ? pia_dout :
                    pl8_cs   ? pl8_dout :
                    via_cs   ? via_dout :
                    spi_cs   ? spi_dout :
                    address[15:8] & 8'hF1; // this is what is normally seen for
                                           // unused address space in the atom due
                                           // to data bus capacitance and pull downs

   // ===============================================================
   // 6522 VIA at 0xB8xx
   // ===============================================================

   m6522 VIA
     (
      .I_RS(address[3:0]),
      .I_DATA(cpu_dout),
      .O_DATA(via_dout),
      .O_DATA_OE_L(),
      .I_RW_L(rnw),
      .I_CS1(via_cs),
      .I_CS2_L(1'b0),
      .O_IRQ_L(via_irq_n),
      .I_CA1(1'b0),
      .I_CA2(1'b0),
      .O_CA2(),
      .O_CA2_OE_L(),
      .I_PA(8'b0),
      .O_PA(),
      .O_PA_OE_L(),
      .I_CB1(1'b0),
      .O_CB1(),
      .O_CB1_OE_L(),
      .I_CB2(1'b0),
      .O_CB2(),
      .O_CB2_OE_L(),
      .I_PB(8'b0),
      .O_PB(),
      .O_PB_OE_L(),
      .I_P2_H(via1_clken),
      .RESET_L(!reset),
      .ENA_4(via4_clken),
      .CLK(clk25)
      );

   // ===============================================================
   // SD Card Interface
   // ===============================================================

   spi SPI
     (
      .clk(clk25),
      .reset(reset),
      .enable(spi_cs & cpu_clken),
      .rnw(rnw),
      .addr(address[2:0]),
      .din(cpu_dout),
      .dout(spi_dout),
      .miso(miso),
      .mosi(mosi),
      .ss(ss),
      .sclk(sclk)
   );

   // ===============================================================
   // Dual Port Video RAM
   // ===============================================================

   // Port A to CPU
   wire        we_a = vid_cs & !rnw;
   // Port B to VDG
   wire [12:0] vid_addr;
   wire [7:0]  vid_data;

   vid_ram
     #(.MEM_INIT_FILE (VID_RAM_INIT_FILE))
   VID_RAM
     (
      // Port A
      .clk_a(clk25),
      .we_a(we_a),
      .addr_a(address[12:0]),
      .din_a(cpu_dout),
      .dout_a(vid_dout),
      // Port B
      .clk_b(clk_vga),
      .addr_b(vid_addr[12:0]),
      .dout_b(vid_data)
      );

   // ===============================================================
   // 6847 VDG
   // ===============================================================

   wire        an_g     = pia_pa[4];
   wire [2:0]  gm       = pia_pa[7:5];
   wire        css      = pia_pc[3];
   wire        inv      = vid_data[7]; // See Atom schematic
   wire        intn_ext = vid_data[6]; // See Atom schematic
   wire        an_s     = vid_data[6]; // See Atom schematic
   wire [10:0] char_a;
   wire [7:0]  char_d;

   mc6847 VDG
     (
      .clk(clk_vga),
      .clk_ena(clk_vga_en),
      .reset(reset),
      .da0(),
      .videoaddr(vid_addr),
      .dd(vid_data),
      .hs_n(),
      .fs_n(fs_n),
      .an_g(an_g),
      .an_s(an_s),
      .intn_ext(intn_ext),
      .gm(gm),
      .css(css),
      .inv(inv),
      .red(red),
      .green(green),
      .blue(blue),
      .hsync(hsync),
      .vsync(vsync),
      .hblank(),
      .vblank(),
      .artifact_en(1'b0),
      .artifact_set(1'b0),
      .artifact_phase(1'b1),
      .cvbs(),
      .black_backgnd(1'b1),
      .char_a(char_a),
      .char_d_o(char_d)
      );

   charrom
     #(.MEM_INIT_FILE (CHARROM_INIT_FILE))
   CHARROM
     (
      .clk(clk_vga),
      .address(char_a),
      .dout(char_d)
      );

endmodule
