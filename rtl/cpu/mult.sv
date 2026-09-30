module mult( 
    input clk,
    input rst_n,                // Reset input
    input mult_en,
    input [31:0] Input_A, 
    input [31:0] Input_B,
    output reg [31:0] mult_output, 
    output reg mult_zero,
    output reg mult_en_r,
    output reg mult_busy          
);

wire [31:0] mult_hh, mult_hl, mult_lh, mult_ll ;
wire [15:0] a_h ;
wire [15:0] b_h ;
wire [15:0] a_l ;
wire [15:0] b_l ;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            mult_en_r <= 'h0 ;
        else if(mult_en)
            mult_en_r <= 'h1 ;        
        else 
            mult_en_r <= 'h0 ;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            mult_output <= 'h0 ;
        else if (mult_en)
            mult_output <= {mult_hh, 32'h0} + {16'h0, mult_hl, 16'h0} +
                           {16'h0, mult_lh, 16'h0} + {32'h0, mult_ll} ;
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            mult_busy <= 'h0 ;
        else
            mult_busy <= mult_en ;                          
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mult_zero <= 'h1 ;
        else if (mult_en)
            mult_zero <= (Input_A=='h0 || Input_B=='h0) ;                          
    end    
    
assign a_h = (mult_en) ? Input_A[31:16] : 16'h0;    
assign b_h = (mult_en) ? Input_B[31:16] : 16'h0;  
assign a_l = (mult_en) ? Input_A[15:0] : 16'h0;    
assign b_l = (mult_en) ? Input_B[15:0] : 16'h0;


assign mult_hh = a_h * b_h ;
assign mult_hl = a_h * b_l ;
assign mult_lh = a_l * b_h ;
assign mult_ll = a_l * b_l ;


endmodule


