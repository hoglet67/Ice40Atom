module sid_filters (
   input                clk, // At least 12Mhz
   input                rst,
   // SID registers.
   input [7:0]          Fc_lo,
   input [7:0]          Fc_hi,
   input [7:0]          Res_Filt,
   input [7:0]          Mode_Vol,
   // Voices - resampled to 13 bit
   input signed [12:0]  voice1,
   input signed [12:0]  voice2,
   input signed [12:0]  voice3,
   //
   input                input_valid,
   input signed [12:0]  ext_in,

   output signed [18:0] sound,
   output               valid
);
   

   wire [3:0]          filt        = Res_Filt[3:0];
   wire [3:0]          res         = Res_Filt[7:4];
   wire [3:0]          volume      = Mode_Vol[3:0];
   wire [2:0]          hp_bp_lp    = Mode_Vol[6:4];
   wire                voice3off = Mode_Vol[7];

   wire signed [17:0] mixer_DC = -475; // NOTE to self: this might be wrong.

   reg signed [17:0] r_Vhp;
   reg signed [17:0] r_Vbp;
   reg signed [17:0] r_dVbp;
   reg signed [17:0] r_Vlp;
   reg signed [17:0] r_dVlp;
   reg signed [17:0] r_Vi ;
   reg signed [17:0] r_Vnf;
   reg signed [17:0] r_Vf;
   reg signed [17:0] r_w0;
   reg signed [17:0] r_q;
   reg signed [18:0] r_vout;
   reg [3:0]         r_state;
   reg               r_done;

   wire [15:0]        val;

   reg [10:0]        divmul [0:15];

   initial
     begin
        divmul[0] <= 1448;        
        divmul[1] <= 1323;
        divmul[2] <= 1218;
        divmul[3] <= 1128;
        divmul[4] <= 1051;
        divmul[5] <= 984;
        divmul[6] <= 925;
        divmul[7] <= 872;
        divmul[8] <= 825;
        divmul[9] <= 783;
        divmul[10] <= 745;
        divmul[11] <= 710;
        divmul[12] <= 679;
        divmul[13] <= 650;
        divmul[14] <= 624;
        divmul[15] <= 599;
     end

   reg signed [17:0] mula;
   reg signed [17:0] mulb;
   reg signed [35:0] mulr;
   reg               mulen;
   
   function signed [17:0] s13_to_18;
      input signed [12:0] a;
      s13_to_18 = { a[12], a[12], a[12], a[12], a[12], a};
   endfunction
   
   always @(posedge clk)
     if (mulen)
       mulr <= mula * mulb;

   wire [10:0] fc = { Fc_hi , Fc_lo[2:0]};
   
   sid_coeffs c
     (
      .clk(clk),
      .addr(fc),
      .val(val)
      );

   always @(posedge clk, posedge rst)
      if (rst)
        begin
           r_done <= 1'b0;
           r_state <= 4'd0;
           r_Vlp <= 0;           
           r_Vbp <= 0;           
           r_Vhp <= 0;           
        end
      else
        begin
           
           mula <= 18'h0;
           mulb <= 18'h0;
           mulen <= 1'b0;

           case (r_state)
             4'd0:
               begin
                  r_done <= 1'b0;
                  if (input_valid)
                    begin
                       r_state <= 4'd1;
                       // Reset Vin, Vnf
                       r_Vi <= 0;
                       r_Vnf <= 0;
                    end
               end

             4'd1:
               begin
                  r_state <= 4'd2;
                  // already have W0 ready. Always positive
                  r_w0 <= {2'b00 & val}; // TODO was signed???
                  // 1st accumulation
                  if (filt[0])
                    r_Vi <= r_Vi + s13_to_18(voice1);
                  else
                    r_Vnf <= r_Vnf + s13_to_18(voice1);
               end

             4'd2:
               begin
                  r_state <= 4'd3;
                  // 2nd accumulation
                  if (filt[1])
                    r_Vi <= r_Vi + s13_to_18(voice2);
                  else
                    r_Vnf <= r_Vnf + s13_to_18(voice2);
                  // Mult
                  mula <= r_w0;
                  mulb <= r_Vhp;
                  mulen <= 1'b1;
               end
             
             4'd3:
               begin
                  r_state <= 4'd4;
                  // 3rd accumulation
                  if (filt[2])
                    r_Vi <= r_Vi + s13_to_18(voice3);
                  else if (!voice3off)
                    r_Vnf <= r_Vnf + s13_to_18(voice3);
                  // Mult
                  mula <= r_w0;
                  mulb <= r_Vbp;
                  mulen <= 1'b1;
                  r_dVbp <= {mulr[35], mulr[35:19]};
               end

             4'd4:
               begin
                  r_state <= 4'd5;
                  // 4th accumulation
                  if (filt[3])
                    r_Vi <= r_Vi + s13_to_18(ext_in);
                  else
                    r_Vnf <= r_Vnf + s13_to_18(ext_in);
                  r_dVlp <= { mulr[35] , mulr[35:19] };
                  r_Vbp <= r_Vbp - r_dVbp;
                  // Get Q, synchronous.
                  r_q <= divmul[res]; // TODO: to_signed
               end

             4'd5:
               begin
                  r_state <= 4'd6;
                  // Ok, we have all summed. We performed multiplications for dVbp and dVlp.
                  // new Vbp already computed.
                  mulen <= 1'b1;
                  mula <= r_q;
                  mulb <= r_Vbp;
                  r_Vlp <= r_Vlp - r_dVlp;
                  // Start computing output;
                  if (hp_bp_lp[1])
                    r_Vf <= r_Vbp;
                  else
                    r_Vf <= 0;
               end

             4'd6:
               begin
                  r_state <= 4'd7;
                  // Adjust Vbp*Q, shift by 10
                  r_Vhp <= {mulr[35], mulr[26:10]} - r_Vlp;
                  if (hp_bp_lp[0])
                    r_Vf <= r_Vf + r_Vlp;
               end

             4'd7: begin
                r_state <= 4'd8;
                r_Vhp <= r_Vhp - r_Vi;
             end

             4'd8:
               begin
                  r_state <= 4'd9;
                  if (hp_bp_lp[2])
                    r_Vf <= r_Vf + r_Vhp;
               end
             
             4'd9:
               begin
                  r_state <= 4'd10;
                  r_Vf <= r_Vf + r_Vnf;
               end

             4'd10:
               begin
                  r_state <= 4'd11;
                  // Add mixer DC
                  r_Vf <= r_Vf + mixer_DC; // TODO: to_signed
               end

             4'd11:
               begin
                  r_state <= 4'd12;
                  // Process volume
                  mulen <= 1'b1;
                  mula <= r_Vf;
                  mulb <= 0;
                  mulb[3:0] <= volume; // TODO: to_signed
               end

             4'd12:
               begin
                  r_state <= 4'd0;
                  r_done <= 1'b1;
                  r_vout[18] <= mulr[35];
                  r_vout[17:0] <= mulr[17:0];
               end
            
           endcase

        end

   assign sound = r_vout;
   assign valid = r_done;

endmodule
