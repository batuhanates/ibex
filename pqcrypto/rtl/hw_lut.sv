
module hw_lut(
    input  logic [3:0] data,
    output logic [2:0] count
  );
  
  always_comb
    case (data)
      4'b0000 : count = 3'b000;
      4'b0001 : count = 3'b001;
      4'b0010 : count = 3'b001;
      4'b0011 : count = 3'b010;
      4'b0100 : count = 3'b001;
      4'b0101 : count = 3'b010;
      4'b0110 : count = 3'b010;
      4'b0111 : count = 3'b011;
      4'b1000 : count = 3'b001;
      4'b1001 : count = 3'b010;
      4'b1010 : count = 3'b010;
      4'b1011 : count = 3'b011;
      4'b1100 : count = 3'b010;
      4'b1101 : count = 3'b011;
      4'b1110 : count = 3'b011;
      4'b1111 : count = 3'b100;
      default : ;
    endcase
endmodule
