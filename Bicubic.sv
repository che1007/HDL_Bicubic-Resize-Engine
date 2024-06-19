module Bicubic #(parameter fraction_bits = 15) 
(
input CLK,
input RST,
input enable,
input [7:0] input_data,
output logic [13:0] iaddr,
output logic ird,
output logic we,
output logic [13:0] waddr,
output logic [7:0] output_data,
input [6:0] V0,
input [6:0] H0,
input [4:0] SW,
input [4:0] SH,
input [5:0] TW,
input [5:0] TH,
output logic DONE
);

localparam IDLE = 4'd0;
localparam UPDATE_Y = 4'd1;
localparam UPDATE_X = 4'd2;
localparam INIT_SELECT = 4'd3;
localparam SELECT = 4'd4;
localparam READ4 = 4'd5;
localparam READ16 = 4'd6;
localparam INTERPOLATE_V = 4'd7;
localparam INTERPOLATE_V2 = 4'd8;
localparam WRITE = 4'd9;
localparam FIHISH = 4'd10;



reg [3:0] currentState, nextState;

reg [5:0] cntx, cnty;
reg [fraction_bits - 1:0] new_x, new_y;
reg [6:0] ori_x, ori_y;
reg [6:0] new_x_integer, new_y_integer, last_y_integer;
reg [7:0] p_minus1, p_0, p_1, p_2, final_p;
reg [3:0] cnt;
reg [fraction_bits:0] point;
reg [7:0] pixelvalue [0:3];
reg [7:0] additional;
reg [7:0] temp [0:2];
reg [5:0] tw_minus1, th_minus1;
reg [4:0] sw_minus1, sh_minus1;
reg [5:0] denominator;
reg [fraction_bits + 9:0] numerator_x, numerator_y, numerator;
wire [fraction_bits + 4:0] motion;
wire x_flag, y_flag, shift_flag;

reg [2:0] times;
reg [10:0] addr;

integer i;


assign motion = (numerator << fraction_bits) / denominator;

assign x_flag = new_x[fraction_bits - 1 : fraction_bits - 5] > 0;
assign y_flag = new_y[fraction_bits - 1 : fraction_bits - 5] > 0;

assign shift_flag = (last_y_integer != new_y_integer);

reg inter_enable;
wire valid;
wire [7:0] p_value;
cubic_interpolation #(.fraction_bits(fraction_bits + 1)) u_cubic_interpolation(.CLK(CLK), .RST(RST), .enable(inter_enable), .p_minus1(p_minus1), .p_0(p_0), .p_1(p_1), .p_2(p_2), .point(point), .valid(valid), .p(p_value));

always @(posedge CLK or posedge RST) begin
    if (RST) begin
        currentState <= IDLE;
    end
    else begin
        currentState <= nextState;
    end
end

always @(*) begin
    case (currentState)
        IDLE: nextState = (enable)? UPDATE_Y : IDLE;
        UPDATE_Y: nextState = UPDATE_X;
        UPDATE_X: nextState = (cnty == 0)? INIT_SELECT : SELECT;
        INIT_SELECT: nextState = (x_flag)? READ16 : READ4;
        SELECT: begin
            case ({x_flag, y_flag})
                2'b00: nextState = WRITE;
                2'b01: nextState = INTERPOLATE_V;
                2'b10: nextState = WRITE;
                2'b11: nextState = INTERPOLATE_V2;
            endcase
        end
        READ4: nextState = (cnt == 5)? WRITE : READ4;
        READ16: nextState = (valid && (times == 0))? WRITE : READ16;
        INTERPOLATE_V: nextState = (valid)? WRITE : INTERPOLATE_V;
        INTERPOLATE_V2: nextState = (cnt == 7)? WRITE : INTERPOLATE_V2;
        WRITE: nextState = ((cntx == (tw_minus1)) && (cnty == (th_minus1)))? FIHISH : UPDATE_Y;
        FIHISH: nextState = FIHISH;
        default: nextState = IDLE;
    endcase
end

always @(posedge CLK or posedge RST) begin
    if (RST) begin
        iaddr <= 0;
        ird <= 0;
        we <= 0;
        waddr <= 0;
        output_data <= 0;
        DONE <= 0;

        cntx <= 0;
        cnty <= 0;
        ori_x <= 0;
        ori_y <= 0;
        new_x <= 0;
        new_y <= 0;
        p_minus1 <= 0; 
        p_0 <= 0;
        p_1 <= 0;
        p_2 <= 0;
        cnt <= 0;
        final_p <= 0;
        point <= 0;
        new_x_integer <= 0;
        new_y_integer <= 0;
        numerator_x <= 0;
        numerator_y <= 0;
        tw_minus1 <= 0;
        th_minus1 <= 0;
        sw_minus1 <= 0;
        sh_minus1 <= 0;
        last_y_integer <= 0;
        inter_enable <= 0;
        numerator <= 0;
        denominator <= 0;
        times <= 0;
        addr <= 0;
        additional <= 0;

        for (i = 0; i < 4; i = i + 1) begin
            pixelvalue[i] <= 0;
        end
        for (i = 0; i < 3; i = i + 1) begin
            temp[i] <= 0;
        end
    end
    else begin
        case (currentState)
            IDLE: begin
                ori_x <= H0;
                ori_y <= V0;
                tw_minus1 <= TW - 1;
                th_minus1 <= TH - 1;
                sw_minus1 <= SW - 1;
                sh_minus1 <= SH - 1;
                DONE <= 0;
                cntx <= 0;
                cnty <= 0;
                numerator <= 0;
                denominator <= TH - 1;
            end
            UPDATE_Y: begin
                we <= 0;
                numerator <= numerator_x;
                denominator <= tw_minus1;
                new_y <= motion[fraction_bits - 1:0];
                new_y_integer <= ori_y + motion[fraction_bits + 4:fraction_bits];

                inter_enable <= 0;
                additional <= (valid)? p_value : input_data;
            end
            UPDATE_X: begin
                new_x <= motion[fraction_bits - 1:0];
                new_x_integer <= ori_x + motion[fraction_bits + 4:fraction_bits];
                if (shift_flag) begin
                    pixelvalue[0] <= pixelvalue[1];
                    pixelvalue[1] <= pixelvalue[2];
                    pixelvalue[2] <= pixelvalue[3];
                    pixelvalue[3] <= additional;
                end
            end
            INIT_SELECT: begin
                times <= 4;
            end
            SELECT: begin
                if (y_flag) begin
                    inter_enable <= 1;
                    p_minus1 <= pixelvalue[0];
                    p_0 <= pixelvalue[1];
                    p_1 <= pixelvalue[2];
                    p_2 <= pixelvalue[3];
                    point <= {new_y[fraction_bits - 1:0], 1'b0};
                end
                else begin
                    final_p <= pixelvalue[1];
                end

                if (x_flag) begin
                    iaddr <= (new_x_integer - 1) * 100 + (new_y_integer + 3);
                end
                else begin
                    iaddr <= new_x_integer * 100 + (new_y_integer + 3);
                end
            end
            WRITE: begin
                addr <= (cnty == th_minus1)? 0 : addr + TW;
                last_y_integer <= new_y_integer;
                we <= 1;
                waddr <= cntx + addr;
                output_data <= final_p;
                cntx <= (cnty == th_minus1)? cntx + 1 : cntx;
                cnty <= (cnty == th_minus1)? 0 : cnty + 1;
                numerator_y <= (cnty == th_minus1)? 0 : numerator_y + (sh_minus1);
                numerator_x <= (cnty == th_minus1)? numerator_x + (sw_minus1) : numerator_x;

                numerator <= (cnty == th_minus1)? 0 : numerator_y + (sh_minus1);
                denominator <= th_minus1;
                cnt <= 0;
            end
            READ4: begin
                ird <= 1;
                cnt <= cnt + 1;
                case (cnt)
                    0: iaddr <= new_x_integer * 100 + (new_y_integer - 1); 
                    1: iaddr <= new_x_integer * 100 + new_y_integer;
                    2: iaddr <= new_x_integer * 100 + (new_y_integer + 1);
                    3: iaddr <= new_x_integer * 100 + (new_y_integer + 2);
                endcase

                case (cnt)
                    2: pixelvalue[0] <= input_data; 
                    3: pixelvalue[1] <= input_data;
                    4: pixelvalue[2] <= input_data;
                    5: pixelvalue[3] <= input_data;
                endcase
                final_p <= pixelvalue[1];
            end
            READ16: begin
                ird <= 1;
                point <= {new_x[fraction_bits - 1:0], 1'b0};
                cnt <= (cnt == 6)? 0 : cnt + 1;
                case (cnt)
                    0: iaddr <= (new_x_integer - 1) * 100 + ((new_y_integer + 3) - times); 
                    1: iaddr <= new_x_integer * 100 + ((new_y_integer + 3) - times);
                    2: iaddr <= (new_x_integer + 1) * 100 + ((new_y_integer + 3) - times);
                    3: iaddr <= (new_x_integer + 2) * 100 + ((new_y_integer + 3) - times);
                endcase

                case (cnt)
                    2: p_minus1 <= input_data; 
                    3: p_0 <= input_data;
                    4: p_1 <= input_data;
                    5: p_2 <= input_data;
                endcase

                if (cnt == 4) begin
                    inter_enable <= 1;
                    times <= times - 1;
                end

                if (valid) begin
                    inter_enable <= 0;
                    pixelvalue[3 - times] <= p_value;
                end
                final_p <= pixelvalue[1];
            end
            INTERPOLATE_V: begin
                inter_enable <= (valid)? 0 : 1;
                final_p <= p_value;
            end
            INTERPOLATE_V2: begin
                cnt <= cnt + 1;
                case (cnt)
                    0: iaddr <= new_x_integer * 100 + (new_y_integer + 3);
                    1: iaddr <= (new_x_integer + 1) * 100 + (new_y_integer + 3);
                    2: iaddr <= (new_x_integer + 2) * 100 + (new_y_integer + 3);
                endcase

                case (cnt)
                    1: temp[0] <= input_data;
                    2: temp[1] <= input_data;
                    3: temp[2] <= input_data;
                endcase

                if (valid) begin
                    final_p <= p_value;
                    p_minus1 <= temp[0];
                    p_0 <= temp[1];
                    p_1 <= temp[2];
                    p_2 <= input_data;
                    point <= {new_x[fraction_bits - 1:0], 1'b0};
                end
            end
            FIHISH: begin
                DONE <= 1;
            end 
        endcase
    end
end

endmodule

module cubic_interpolation #(parameter fraction_bits = 16)
(
input CLK,
input RST,
input enable,
input [7:0] p_minus1,
input [7:0] p_0,
input [7:0] p_1,
input [7:0] p_2,
input [fraction_bits - 1:0] point,
output reg valid,
output reg [7:0] p
);

localparam CAL = 2'b01;
localparam FINISH = 2'b10;
reg [1:0] currentState, nextState;


wire signed [fraction_bits + 9:0] a, b, c, d;

wire signed [fraction_bits + 27:0] constx;
reg [1:0] inter_cnt;
reg signed [fraction_bits + 27:0] temp_p;
reg signed [fraction_bits + 9:0] const_temp;


reg flag;
wire [fraction_bits - 1:0] x_temp;


multiply u_multiply(.CLK(CLK), .RST(RST), .a(x_temp), .b(point), .ans(x_temp), .flag(flag));
signed_multiply u_signed_multiply(.CLK(CLK), .RST(RST), .a(const_temp), .b({1'b0, x_temp}), .ans(constx));

assign a = ((-p_minus1 + ({p_0, 1'b0} + p_0)) + (p_2 - ({p_1, 1'b0} + p_1))) << (fraction_bits - 1);
assign b = (({p_minus1, 1'b0} - ({p_0, 2'b0} + p_0)) + ({p_1, 2'b0} - p_2)) << (fraction_bits - 1);
assign c = (-p_minus1 + p_1) << (fraction_bits - 1);
assign d = {p_0, 1'b0} << (fraction_bits - 1);

always @(posedge CLK or posedge RST) begin
    if (RST) begin
        currentState <= CAL;
    end
    else begin
        currentState <= nextState;
    end
end

always @(*) begin
    case (currentState)
        CAL: nextState = (inter_cnt == 3)? FINISH : CAL;
        FINISH: nextState = CAL;
        default: nextState = CAL;
    endcase
end

always @(*) begin
    case (inter_cnt)
        0: const_temp = c;
        1: const_temp = b;
        default: const_temp = a;
    endcase
end

always @(posedge CLK or posedge RST) begin
    if (RST) begin
        inter_cnt <= 0;
        temp_p <= 0;
        flag <= 1;
    end
    else begin
        case (currentState)
            CAL: begin
                if (enable) begin
                    inter_cnt <= inter_cnt + 1;
                    flag <= 0;
                end
                temp_p <= (inter_cnt == 0)? d : temp_p + constx;
            end
            FINISH: begin
                flag <= 1;
            end 
        endcase
    end
end

always @(*) begin
    valid = (currentState == FINISH);
    p = (temp_p[fraction_bits + 27])? 0 : temp_p[fraction_bits+7:fraction_bits] + temp_p[fraction_bits - 1];
end

endmodule

module multiply #(parameter MUL_WIDTH = 16, parameter MUL_RESULT = 32)
(
input                        CLK,
input                        RST,
input  [MUL_WIDTH-1:0]         a,
input  [MUL_WIDTH-1:0]         b,
input                       flag,
output [MUL_WIDTH-1:0]       ans
);

reg [MUL_RESULT-1:0]         add;

wire [MUL_WIDTH-1:0]   mul_a_reg;
wire [MUL_WIDTH-1:0]   mul_b_reg;


wire [16:0]   stored0, stored2, stored4, stored6, stored8, stored10, stored12, stored14;
wire [16:0]   stored1, stored3, stored5, stored7, stored9, stored11, stored13, stored15;

assign mul_a_reg = a ;
assign mul_b_reg = b ;

assign stored0 = mul_b_reg[0]? mul_a_reg : 0;
assign stored1 = mul_b_reg[1]? mul_a_reg : 0;

assign stored2 = mul_b_reg[2]? mul_a_reg : 0;
assign stored3 = mul_b_reg[3]? mul_a_reg : 0;

assign stored4 = mul_b_reg[4]? mul_a_reg : 0;
assign stored5 = mul_b_reg[5]? mul_a_reg : 0;

assign stored6 = mul_b_reg[6]? mul_a_reg : 0;
assign stored7 = mul_b_reg[7]? mul_a_reg : 0;

assign stored8 = mul_b_reg[8]? mul_a_reg : 0;
assign stored9 = mul_b_reg[9]? mul_a_reg : 0;

assign stored10 = mul_b_reg[10]? mul_a_reg : 0;
assign stored11 = mul_b_reg[11]? mul_a_reg : 0;

assign stored12 = mul_b_reg[12]? mul_a_reg : 0;
assign stored13 = mul_b_reg[13]? mul_a_reg : 0;

assign stored14 = mul_b_reg[14]? mul_a_reg : 0;
assign stored15 = mul_b_reg[15]? mul_a_reg : 0;

always @(posedge CLK or posedge RST) begin
	if (RST) begin		
		add <= 0;	
	end

	else begin
        add <= (((({stored1, 1'b0} + stored0) + {({stored3, 1'b0} + stored2), 2'b0}) + 
               {(({stored5, 1'b0} + stored4) + {({stored7, 1'b0} + stored6),2'b0}), 4'b0}) +

               {((({stored9, 1'b0} + stored8) + {({stored11, 1'b0} + stored10), 2'b0}) + 
               {(({stored13, 1'b0} + stored12) + {({stored15, 1'b0} + stored14),2'b0}), 4'b0}), 8'b0});
	end
end

assign ans = (flag)? b : add[31:16];

endmodule

module signed_multiply #(parameter MUL_WIDTH = 26, parameter MUL_RESULT = 43)
(
input                    CLK,
input                    RST,
input  [MUL_WIDTH-1:0]     a,
input  [16:0]              b,
output [MUL_RESULT:0]    ans
);


reg                             msb;
reg [MUL_RESULT-1:0]            add;

wire [MUL_WIDTH-2:0]      mul_a_reg;
wire [16:0]               mul_b_reg;

wire [MUL_WIDTH-2:0]          inv_a;
wire [MUL_RESULT-1:0]       inv_add;

wire [25:0]   stored0, stored2, stored4, stored6, stored8, stored10, stored12, stored14;
wire [25:0]   stored1, stored3, stored5, stored7, stored9, stored11, stored13, stored15;

assign inv_a = ~a[24:0] + 1;

assign mul_a_reg = (a[25] == 0)? a[24:0] : inv_a;
assign mul_b_reg = b;
 
assign stored0 = mul_b_reg[0]? mul_a_reg : 0;
assign stored1 = mul_b_reg[1]? mul_a_reg : 0;

assign stored2 = mul_b_reg[2]? mul_a_reg : 0;
assign stored3 = mul_b_reg[3]? mul_a_reg : 0;

assign stored4 = mul_b_reg[4]? mul_a_reg : 0;
assign stored5 = mul_b_reg[5]? mul_a_reg : 0;

assign stored6 = mul_b_reg[6]? mul_a_reg : 0;
assign stored7 = mul_b_reg[7]? mul_a_reg : 0;

assign stored8 = mul_b_reg[8]? mul_a_reg : 0;
assign stored9 = mul_b_reg[9]? mul_a_reg : 0;

assign stored10 = mul_b_reg[10]? mul_a_reg : 0;
assign stored11 = mul_b_reg[11]? mul_a_reg : 0;

assign stored12 = mul_b_reg[12]? mul_a_reg : 0;
assign stored13 = mul_b_reg[13]? mul_a_reg : 0;

assign stored14 = mul_b_reg[14]? mul_a_reg : 0;
assign stored15 = mul_b_reg[15]? mul_a_reg : 0;

always @(posedge CLK or posedge RST) begin
	if (RST) begin		
		msb<=0;
		add<=0;	
	end

	else begin
		msb <= a[25];
		
        if (a != 0) begin
            add <= (((({stored1, 1'b0} + stored0) + {({stored3, 1'b0} + stored2), 2'b0}) + 
                    {(({stored5, 1'b0} + stored4) + {({stored7, 1'b0} + stored6),2'b0}), 4'b0}) +

                    {((({stored9, 1'b0} + stored8) + {({stored11, 1'b0} + stored10), 2'b0}) + 
                    {(({stored13, 1'b0} + stored12) + {({stored15, 1'b0} + stored14),2'b0}), 4'b0}), 8'b0}) >> 16;
        end
        else begin
            add <= 0;
        end
		
	end
end

assign ans = (msb)? -add : add;

endmodule