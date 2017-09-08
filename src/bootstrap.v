module bootstrap
  (

   // Clock needs to be clk100 (i.e. >> SCK)
   input         clk,
   output reg    booting = 1'b1,
   output        progress,

   // SPI Slave Interface (runs at 20MHz)
   input         SCK,
   input         SSEL,
   input         MOSI,
   output        MISO,

   // RAM from Atom
   input         atom_RAMCS_b,
   input         atom_RAMOE_b,
   input         atom_RAMWE_b,
   input [17:0]  atom_RAMA,
   input [7:0]   atom_RAMDin,

   // RAM to external SRAM
   output        ext_RAMCS_b,
   output        ext_RAMOE_b,
   output        ext_RAMWE_b,
   output [17:0] ext_RAMA,
   output [7:0]  ext_RAMDin
   );

   // ===============================================================
   // Local registers
   // ===============================================================

   reg           boot_RAMWE_b;
   reg [17:0]    boot_RAMA;
   reg [7:0]     boot_RAMDin;
   reg [17:0]    boot_ENDA;

   // ===============================================================
   // RAM Multiplexor (between the Atom and the boot Loader)
   // ===============================================================

   assign ext_RAMCS_b = booting ? 1'b0         : atom_RAMCS_b;
   assign ext_RAMOE_b = booting ? 1'b1         : atom_RAMOE_b;
   assign ext_RAMWE_b = booting ? boot_RAMWE_b : atom_RAMWE_b;
   assign ext_RAMA    = booting ? boot_RAMA    : atom_RAMA;
   assign ext_RAMDin  = booting ? boot_RAMDin  : atom_RAMDin;

   // ===============================================================
   // Simple SPI Slave
   // ===============================================================

   // See: http://www.fpga4fun.com/SPI2.html

   // sync SCK to the FPGA clock using a 3-bits shift register
   reg [2:0]     SCKr;  always @(posedge clk) SCKr <= {SCKr[1:0], SCK};
   wire          SCK_risingedge = (SCKr[2:1]==2'b01);  // now we can detect SCK rising edges
   wire          SCK_fallingedge = (SCKr[2:1]==2'b10);  // and falling edges

   // same thing for SSEL
   reg [2:0]     SSELr;  always @(posedge clk) SSELr <= {SSELr[1:0], SSEL};
   wire          SSEL_active = ~SSELr[1];  // SSEL is active low
   wire          SSEL_startmessage = (SSELr[2:1]==2'b10);  // message starts at falling edge

   // and for MOSI
   reg [1:0]     MOSIr;  always @(posedge clk) MOSIr <= {MOSIr[0], MOSI};
   wire          MOSI_data = MOSIr[1];

   // we handle SPI in 8-bits format, so we need a 3 bits counter to count the bits as they come in
   reg [2:0]     bitcnt;

   reg           byte_received;  // high when a byte has been received
   reg [7:0]     byte_data_received;

   always @(posedge clk)
     begin
        if(~SSEL_active)
          bitcnt <= 3'b000;
        else
          if(SCK_risingedge)
            begin
               bitcnt <= bitcnt + 3'b001;
               // implement a shift-left register (since we receive the data MSB first)
               byte_data_received <= {byte_data_received[6:0], MOSI_data};
            end
     end

   always @(posedge clk) byte_received <= SSEL_active && SCK_risingedge && (bitcnt==3'b111);

   assign progress = byte_received;

   assign MISO = 1'b1;

   // ===============================================================
   // Bootstrap state machine
   // ===============================================================

`define st_idle               4'h0
`define st_wait_for_start_lo  4'h1
`define st_wait_for_start_mid 4'h2
`define st_wait_for_start_hi  4'h3
`define st_wait_for_end_lo    4'h4
`define st_wait_for_end_mid   4'h5
`define st_wait_for_end_hi    4'h6
`define st_wait_for_byte      4'h7
`define st_write_1            4'h8
`define st_write_2            4'h9
`define st_write_3            4'hA
`define st_write_4            4'hB
`define st_done               4'hC

   reg [3:0] state = `st_idle;

   always @(posedge clk)
     case (state)
       `st_idle:
         begin
            booting      <= 1'b1;
            boot_RAMWE_b <= 1'b1;
            if (SSEL_startmessage)
              state <= `st_wait_for_start_lo;
         end
       `st_wait_for_start_lo:
         if (byte_received)
           begin
              boot_RAMA[7:0] <= byte_data_received;
              state <= `st_wait_for_start_mid;
           end
       `st_wait_for_start_mid:
         if (byte_received)
           begin
              boot_RAMA[15:8] <= byte_data_received;
              state <= `st_wait_for_start_hi;
           end
       `st_wait_for_start_hi:
         if (byte_received)
           begin
              boot_RAMA[17:16] <= byte_data_received[1:0];
              state <= `st_wait_for_end_lo;
           end
       `st_wait_for_end_lo:
         if (byte_received)
           begin
              boot_ENDA[7:0] <= byte_data_received;
              state <= `st_wait_for_end_mid;
           end
       `st_wait_for_end_mid:
         if (byte_received)
           begin
              boot_ENDA[15:8] <= byte_data_received;
              state <= `st_wait_for_end_hi;
           end
       `st_wait_for_end_hi:
         if (byte_received)
           begin
              boot_ENDA[17:16] <= byte_data_received[1:0];
              state <= `st_wait_for_byte;
           end
       `st_wait_for_byte:
         if (byte_received)
           begin
              boot_RAMDin <= byte_data_received;
              state <= `st_write_1;
           end
       `st_write_1:
         begin
            boot_RAMWE_b <= 1'b0;
            state <= `st_write_2;
         end
       `st_write_2:
         begin
            state <= `st_write_3;
         end
       `st_write_3:
         begin
            boot_RAMWE_b <= 1'b1;
            state <= `st_write_4;
         end
       `st_write_4:
         begin
            if (boot_RAMA == boot_ENDA)
              begin
                 state <= `st_done;
              end
            else
              begin
                 boot_RAMA <= boot_RAMA + 1;
                 state <= `st_wait_for_byte;
              end
         end
       `st_done:
         begin
             booting <= 1'b0;
         end

       default:
         state <= `st_idle;

     endcase

endmodule
