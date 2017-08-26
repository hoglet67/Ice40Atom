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

module atom (
             input         clk100,
             output        led1,
             output        led2,
             output        led3,
             output        led4,
             input         sw1_1,
             input         sw1_2,
             input         sw2_1,
             input         sw2_2,
             input         sw3,
             input         sw4,
             output        RAMWE_b,
             output        RAMOE_b,
             output        RAMCS_b,
             output [17:0] ADR,
             inout [7:0]   DAT,
             input         ps2_clk,
             input         ps2_data,
             output [2:0]  r,
             output [2:0]  g,
             output [1:0]  b,
             output        hsync,
             output        vsync
             );

   // ===============================================================
   // CPU Clock generation
   // ===============================================================

   reg [1:0]  clkpre = 2'b00;     // prescaler, from 100MHz to 25MHz
   reg [4:0]  clkdiv = 5'b00000;  // divider, from 25MHz down to 1MHz

   always @(posedge clk100)
     begin
        clkpre <= clkpre + 1;
        if (clkpre == 'b0)
          if (clkdiv == 24)
            clkdiv = 0;
          else
            clkdiv = clkdiv + 1;
     end

   wire clk_cpu = clkdiv[4];

   // It's pretty arbitrary when in the cycle the write actually happens
   wire wegate = (clkdiv == 0);

   // ===============================================================
   // VGA Clock generation
   // ===============================================================

   wire clk_vga = clkpre[1];
   reg  clk_vga_en = 0;

   always @(posedge clk_vga)
     clk_vga_en <= !clk_vga_en;

   // ===============================================================
   // Reset generation
   // ===============================================================

   reg [9:0] pwr_up_reset_counter = 0; // hold reset low for ~1ms
   wire      pwr_up_reset_n = &pwr_up_reset_counter;
   reg       hard_reset_n;

   always @(posedge clk_cpu)
     begin
        if (!pwr_up_reset_n)
          pwr_up_reset_counter <= pwr_up_reset_counter + 1;
        hard_reset_n <= sw4 & pwr_up_reset_n;
     end

   wire reset = !hard_reset_n | !break_n;

   // ===============================================================
   // LEDs
   // ===============================================================

   assign led1 = reset;    // blue
   assign led2 = 1'b1;     // green
   assign led3 = 1'b0;     // yellow
   assign led4 = 1'b0;     // red

   // ===============================================================
   // Keyboard
   // ===============================================================

   wire rept_n;
   wire shift_n;
   wire ctrl_n;
   wire break_n;
   wire [3:0] row = pia_pa_r[3:0];
   wire [5:0] keyout;

   keyboard KBD
     (
      .CLK(clk_vga),
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
   // Cassette -- TODO
   // ===============================================================

   wire       cas_in = 1'b1;
   wire       cas_tone = 1'b1;

   // ===============================================================
   // External RAM
   // ===============================================================

   assign RAMCS_b = 1'b0;
   assign RAMOE_b = !rnw;
   assign RAMWE_b = rnw  | wegate;
   assign ADR = { 2'b00, address };

`ifdef use_sb_io
   // IceStorm cannot infer bidirectional I/Os
   wire [7:0] data_pins_in;
   wire [7:0] data_pins_out = cpu_dout;
   wire       data_pins_out_en = !(rnw | wegate); // Added wegate to avoid bus conflicts
   SB_IO #(
           .PIN_TYPE(6'b 1010_01)
           ) sram_data_pins [7:0] (
                                   .PACKAGE_PIN(DAT),
                                   .OUTPUT_ENABLE(data_pins_out_en),
                                   .D_OUT_0(data_pins_out),
                                   .D_IN_0(data_pins_in)
                                   );
`else
   assign DAT = (rnw | wegate) ? 8'bz : cpu_dout;
   wire [7:0] data_pins_in = DAT;
`endif

   // ===============================================================
   // 6522 VIA at 0xB8xx - TODO
   // ===============================================================

   wire [7:0] via_dout = 8'hB1;

   // ===============================================================
   // 8255 PIA at 0xB0xx
   // ===============================================================

   // TODO - this model is still very crude
   // e.g. writing to B003 does not have the correct effect

   reg [7:0]  pia_dout;
   reg [7:0]  pia_pa_r = 8'b00000000;
   reg [3:0]  pia_pc_r = 4'b0000;
   wire [7:0] pia_pa   = { pia_pa_r };
   wire [7:0] pia_pb   = { shift_n, ctrl_n, keyout };
   wire [7:0] pia_pc   = { fs_n, rept_n, cas_in, cas_tone, pia_pc_r};

   always @(posedge clk_cpu)
     begin
        if (pia_cs && !rnw)
          case (address[1:0])
            2'b00: pia_pa_r <= cpu_dout;
            2'b10: pia_pc_r <= cpu_dout[3:0];
          endcase
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
   reg [7:0]   cpu_dout;
   wire [15:0] address_c;
   reg [15:0]  address;
   reg         rnw;
   wire        rnw_c;

   // Arlet's 6502 core is one of the smallest available
   cpu CPU
     (
      .clk(clk_cpu),
      .reset(reset),
      .AB(address_c),
      .DI(cpu_din),
      .DO(cpu_dout_c),
      .WE(rnw_c),
      .IRQ(1'b0),
      .NMI(1'b0),
      .RDY(1'b1)
      );

   // The outputs of Arlets's 6502 core need registing
   always @(posedge clk_cpu)
     begin
        address  <= address_c;
        cpu_dout <= cpu_dout_c;
        rnw      <= !rnw_c;
     end

   // ===============================================================
   // Address decoding logic and data in multiplexor
   // ===============================================================

   wire        rom_cs = (address[15:12] == 4'b1100 || address[15:12] == 4'b1111);
   wire        pia_cs = (address[15:10] == 6'b101100);
   wire        via_cs = (address[15:10] == 6'b101110);
   wire        ram_cs = (address[15]    == 1'b0);
   wire        vid_cs = (address[15:12] == 4'b1000);

   assign cpu_din = ram_cs   ? data_pins_in :
                    vid_cs   ? vid_dout :
                    rom_cs   ? rom_dout :
                    pia_cs   ? pia_dout :
                    via_cs   ? via_dout :
                    address[15:8] & 8'hF1; // this is what is normally seen for
   // unused address space in the atom due
   // to data bus capacitance and pull downs

   // ===============================================================
   // BASIC and MOS ROM
   // ===============================================================

   wire [7:0]  rom_dout;
   rom_c000_f000 ROM
     (
      .clk(clk_cpu),
      .address(address_c[12:0]), // fed directly from CPU to mask BRAM register
      .dout(rom_dout)
      );

   // ===============================================================
   // Dual Port Video RAM
   // ===============================================================

   // Port A to CPU
   wire [7:0]  vid_dout;
   wire        we_a = vid_cs & !rnw;
   // Port B to VDG
   wire [12:0] vid_addr;
   wire [7:0]  vid_data;

   vid_ram VID_RAM
     (
      // Port A
      .clk_a(!clk_cpu),    // Clock of negative edge to mask register latency
      .we_a(we_a),
      .addr_a(address[10:0]),
      .din_a(cpu_dout),
      .dout_a(vid_dout),
      // Port B
      .clk_b(clk_vga),
      .addr_b(vid_addr[10:0]),
      .dout_b(vid_data)
      );

   // ===============================================================
   // 6847 VDG
   // ===============================================================

   wire        fs_n;
   wire        an_g     = pia_pa[4];
   wire [2:0]  gm       = pia_pa[7:5];
   wire        css      = pia_pc[3];
   wire        inv      = vid_data[7]; // See Atom schematic
   wire        intn_ext = vid_data[6]; // See Atom schematic
   wire        an_s     = vid_data[6]; // See Atom schematic
   wire [10:0] char_a;
   wire [7:0]  char_d;
   wire [3:0]  red;
   wire [3:0]  green;
   wire [3:0]  blue;

   assign r = red[3:1];
   assign g = green[3:1];
   assign b = blue[3:2];

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
      .black_backgnd(1'b0),
      .char_a(char_a),
      .char_d_o(char_d)
      );

   charrom CHARROM
     (
      .clk(clk_vga),
      .address(char_a),
      .dout(char_d)
      );

endmodule
