// `define use_pll
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
               output [2:0]  r,
               output [2:0]  g,
               output [1:0]  b,
               output        hsync,
               output        vsync
);

   // CLKSPEED is the main clock speed
   parameter CLKSPEED = 25000000;

   // CPU signals
   wire        clk;
   wire [7:0]  cpu_din;
   reg [7:0]   cpu_dout;
   reg [15:0]  address;
   reg         rnw;
   wire [15:0] address_c;
   wire [7:0]  cpu_dout_c;
   wire        rnw_c;

   reg         sw4_sync;
   wire        reset;

   wire        rom_cs = (address[15:12] == 4'b1100 || address[15:12] == 4'b1111);
   wire        pia_cs = (address[15:10] == 6'b101100);
   wire        via_cs = (address[15:10] == 6'b101110);
   wire        ram_cs = (address[15]    == 1'b0);
   wire        vid_cs = (address[15:12] == 4'b1000);


//   wire        page0_cs = (address[15:9] == 7'b0000000);
//   wire [7:0]  page0_dout;

   
   wire [7:0]  vid_dout;
   wire [7:0]  rom_dout;
   wire [7:0]  via_dout = 8'hB1;
   reg  [7:0]  pia_dout;

   wire [3:0] red;
   wire [3:0] green;
   wire [3:0] blue;

   assign r = red[3:1];
   assign g = green[3:1];
   assign b = blue[3:2];



   // External RAM signals
   wire         wegate;
   assign RAMCS_b = 1'b0;
   assign RAMOE_b = !rnw;
   assign RAMWE_b = rnw  | wegate;
   assign ADR = { 2'b00, address };


`ifdef use_sb_io   
   // So instead we must instantiate a SB_IO block
   wire [7:0]   data_pins_in;
   wire [7:0]   data_pins_out = cpu_dout;
   wire         data_pins_out_en = !(rnw | wegate); // Added wegate to avoid bus conflicts
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
   wire [7:0]   data_pins_in = DAT;
`endif

   // PIA PA is an output port
   // PIA PB is an input port
   // PIA PC is an input / output port
   reg [7:0]  pia_pa_r;
   reg [3:0]  pia_pc_r = 4'b0;
   wire       rept_n = 1'b1;
   wire       shift_n = 1'b1;
   wire       ctrl_n = 1'b1;
   wire       cas_in = 1'b1;
   wire       cas_tone = 1'b1;
   wire [5:0] keyboard = 6'b11111;

   wire [7:0] pia_pa = { pia_pa_r };
   wire [7:0] pia_pb = { shift_n, ctrl_n, keyboard };
   wire [7:0] pia_pc = { fs_n, rept_n, cas_in, cas_tone, pia_pc_r};

   always @(posedge clk)
     begin
        if (pia_cs && !rnw)
          case (address[1:0])
            2'b00: pia_pa_r <= cpu_dout;
            2'b10: pia_pc_r <= cpu_dout[3:0];
          endcase
     end

   always @(address, pia_pa, pia_pb, pia_pc)
     begin
        case(address[1:0])
          2'b00: pia_dout <= pia_pa;
          2'b01: pia_dout <= pia_pb;
          2'b10: pia_dout <= pia_pc;
          default:
            pia_dout <= 0;
        endcase
     end

   // Data Multiplexor
   // page0_cs ? page0_dout :

   assign cpu_din = ram_cs   ? data_pins_in :
                    vid_cs   ? vid_dout :
                    rom_cs   ? rom_dout :
                    pia_cs   ? pia_dout :
                    via_cs   ? via_dout :
                    8'hff;

`ifdef use_pll
   // PLL to go from 100MHz to 40MHz
   //
   // In PHASE_AND_DELAY_MODE:
   //     FreqOut = FreqRef * (DIVF + 1) / (DIVR + 1)
   //     (DIVF: 0..63)
   //     (DIVR: 0..15)
   //     (DIVQ: 1..6, apparantly not used in this mode)
   //
   // The valid PLL output range is 16 - 275 MHz.
   // The valid PLL VCO range is 533 - 1066 MHz.
   // The valid phase detector range is 10 - 133MHz.
   // The valid input frequency range is 10 - 133MHz.
   //
   //
   // icepll -i 100 -o 40
   // F_PLLIN:   100.000 MHz (given)
   // F_PLLOUT:   40.000 MHz (requested)
   // F_PLLOUT:   40.000 MHz (achieved)
   //
   // FEEDBACK: SIMPLE
   // F_PFD:   20.000 MHz
   // F_VCO:  640.000 MHz
   //
   // DIVR:  4 (4'b0100)
   // DIVF: 31 (7'b0011111)
   // DIVQ:  4 (3'b100)
   //
   // FILTER_RANGE: 2 (3'b010)


   wire         PLL_BYPASS = 0;
   wire         PLL_RESETB = 1;
   wire         LOCK;
   SB_PLL40_CORE #(
        .FEEDBACK_PATH("SIMPLE"),
        .DELAY_ADJUSTMENT_MODE_FEEDBACK("FIXED"),
        .DELAY_ADJUSTMENT_MODE_RELATIVE("FIXED"),
        .PLLOUT_SELECT("GENCLK"),
        .SHIFTREG_DIV_MODE(1'b0),
        .FDA_FEEDBACK(4'b0000),
        .FDA_RELATIVE(4'b0000),
        .DIVR(4'b0100),
        .DIVF(7'b0011111),
        .DIVQ(3'b100),
        .FILTER_RANGE(3'b010),
   ) uut (
        .REFERENCECLK   (clk100),
        .PLLOUTGLOBAL   (clk),
        .PLLOUTCORE     (wegate),
        .BYPASS         (PLL_BYPASS),
        .RESETB         (PLL_RESETB),
        .LOCK           (LOCK)
   );
`else // !`ifdef use_pll
   wire LOCK = 1'b1;
//   reg [2:0]    clkpre = 3;b00;  // prescaler
   reg [1:0]    clkdiv = 2'b00;  // divider
   always @(posedge clk100)
     begin
//        clkpre <= clkpre + 1;
//        if (clkpre == 'b0) begin
           case (clkdiv)
             2'b11: clkdiv <= 2'b10;  // rising edge of clk
             2'b10: clkdiv <= 2'b00;  // wegate low
             2'b00: clkdiv <= 2'b01;  // wegate low
             2'b01: clkdiv <= 2'b11;
           endcase
//        end
     end
   assign clk = clkdiv[1];
   assign wegate = clkdiv[0];
`endif

   always @(posedge clk)
     begin
        sw4_sync <= sw4;
     end

   assign reset = !sw4_sync;

   assign led1 = reset;    // blue
   assign led2 = LOCK;     // green
   assign led3 = 0;        // yellow
   assign led4 = 0;        // red

   cpu CPU
     (
      .clk(clk),
      .reset(reset),
      .AB(address_c),
      .DI(cpu_din),
      .DO(cpu_dout_c),
      .WE(rnw_c),
      .IRQ(1'b0),
      .NMI(1'b0),
      .RDY(1'b1)
      );
   always @(posedge clk)
     begin
        address  <= address_c;
        cpu_dout <= cpu_dout_c;
        rnw      <= !rnw_c;
     end


   // A block RAM - clocked off negative edge to mask output register
   rom_c000_f000 ROM
     (
      .clk(clk),
      .address(address_c[12:0]),
      .dout(rom_dout)
      );


   // Page zero RAM
//   ram_1024_8 RAM
//     (
//      .din(cpu_dout),
//      .dout(page0_dout),
//      .address(address[9:0]),
//      .rnw(rnw),
//      .clk(!clk),
//      .cs(page0_cs)
//      );

   wire        clk_vga = clk;
   reg         clk_vga_en = 0;
   wire [12:0] vid_addr;
   wire [7:0]  vid_data;
   wire        hs_n;
   wire        fs_n;

   // 6847 mode selectyion
   wire        an_g     = pia_pa[4];
   wire [2:0]  gm       = pia_pa[7:5];   
   wire        css      = pia_pc[3];
   wire        inv      = vid_data[7];
   wire        intn_ext = vid_data[6];
   wire        an_s     = vid_data[6];
   wire [10:0] char_a;
   wire [7:0]  char_d;

   always @(posedge clk)
     clk_vga_en <= !clk_vga_en;

   charrom CHARROM
     (
      .clk(clk_vga),
      .address(char_a),
      .dout(char_d)
      );

   wire        we_a = vid_cs & !rnw;

   vid_ram VID_RAM
     (
      // Port A
      .clk_a(!clk),    // Clock of negative edge to mask register latency
      .we_a(we_a),
      .addr_a(address[10:0]),
      .din_a(cpu_dout),
      .dout_a(vid_dout),
      // Port B
      .clk_b(clk_vga),
      .addr_b(vid_addr[10:0]),
      .dout_b(vid_data)
      );

   mc6847 CTRC
     (
      .clk(clk_vga),
      .clk_ena(clk_vga_en),
      .reset(reset),
      .da0(),
      .videoaddr(vid_addr),
      .dd(vid_data),
      .hs_n(hs_n),
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

endmodule
