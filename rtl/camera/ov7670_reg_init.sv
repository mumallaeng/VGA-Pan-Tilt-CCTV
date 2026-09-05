`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: ov7670_reg_init
// Description: Programs the OV7670 with the validated 75-entry QVGA RGB565 table.
//////////////////////////////////////////////////////////////////////////////////

module ov7670_reg_init #(
    parameter integer STARTUP_DELAY_CYCLES = 1_000_000,
    parameter integer RESET_DELAY_CYCLES   = 500_000
) (
    input logic clk_100MHz,
    input logic rst,

    output logic       sccb_start,
    output logic [7:0] sccb_reg_addr,
    output logic [7:0] sccb_reg_data,
    input  logic       sccb_busy,
    input  logic       sccb_done,

    output logic       init_done,
    output logic [6:0] init_index
);

    localparam integer REG_COUNT = 75;
    localparam integer DELAY_CNT_WIDTH =
        (STARTUP_DELAY_CYCLES <= 1) ? 1 : $clog2(
        STARTUP_DELAY_CYCLES + 1
    );

    typedef enum logic [2:0] {
        S_POWERUP_WAIT,
        S_ISSUE_WRITE,
        S_WAIT_WRITE,
        S_RESET_WAIT,
        S_NEXT_REGISTER,
        S_DONE
    } init_state_e;

    init_state_e state;
    logic [DELAY_CNT_WIDTH-1:0] delay_count;

    function automatic logic [15:0] register_word(input logic [6:0] index);
        case (index)
            7'd0:    register_word = 16'h12_80;
            7'd1:    register_word = 16'hFF_F0;
            7'd2:    register_word = 16'h12_14;
            7'd3:    register_word = 16'h11_80;
            7'd4:    register_word = 16'h0C_04;
            7'd5:    register_word = 16'h3E_19;
            7'd6:    register_word = 16'h04_00;
            7'd7:    register_word = 16'h40_D0;
            7'd8:    register_word = 16'h3A_04;
            7'd9:    register_word = 16'h14_18;
            7'd10:   register_word = 16'h4F_B3;
            7'd11:   register_word = 16'h50_B3;
            7'd12:   register_word = 16'h51_00;
            7'd13:   register_word = 16'h52_3D;
            7'd14:   register_word = 16'h53_A7;
            7'd15:   register_word = 16'h54_E4;
            7'd16:   register_word = 16'h58_9E;
            7'd17:   register_word = 16'h3D_C0;
            7'd18:   register_word = 16'h17_15;
            7'd19:   register_word = 16'h18_03;
            7'd20:   register_word = 16'h32_00;
            7'd21:   register_word = 16'h19_03;
            7'd22:   register_word = 16'h1A_7B;
            7'd23:   register_word = 16'h03_00;
            7'd24:   register_word = 16'h0F_41;
            7'd25:   register_word = 16'h1E_30;
            7'd26:   register_word = 16'h33_0B;
            7'd27:   register_word = 16'h3C_78;
            7'd28:   register_word = 16'h69_00;
            7'd29:   register_word = 16'h74_00;
            7'd30:   register_word = 16'hB0_84;
            7'd31:   register_word = 16'hB1_0C;
            7'd32:   register_word = 16'hB2_0E;
            7'd33:   register_word = 16'hB3_80;
            7'd34:   register_word = 16'h70_3A;
            7'd35:   register_word = 16'h71_35;
            7'd36:   register_word = 16'h72_11;
            7'd37:   register_word = 16'h73_F1;
            7'd38:   register_word = 16'hA2_02;
            7'd39:   register_word = 16'h7A_20;
            7'd40:   register_word = 16'h7B_10;
            7'd41:   register_word = 16'h7C_1E;
            7'd42:   register_word = 16'h7D_35;
            7'd43:   register_word = 16'h7E_5A;
            7'd44:   register_word = 16'h7F_69;
            7'd45:   register_word = 16'h80_76;
            7'd46:   register_word = 16'h81_80;
            7'd47:   register_word = 16'h82_88;
            7'd48:   register_word = 16'h83_8F;
            7'd49:   register_word = 16'h84_96;
            7'd50:   register_word = 16'h85_A3;
            7'd51:   register_word = 16'h86_AF;
            7'd52:   register_word = 16'h87_C4;
            7'd53:   register_word = 16'h88_D7;
            7'd54:   register_word = 16'h89_E8;
            7'd55:   register_word = 16'h13_E0;
            7'd56:   register_word = 16'h00_00;
            7'd57:   register_word = 16'h10_00;
            7'd58:   register_word = 16'h0D_40;
            7'd59:   register_word = 16'h14_18;
            7'd60:   register_word = 16'hA5_05;
            7'd61:   register_word = 16'hAB_07;
            7'd62:   register_word = 16'h24_95;
            7'd63:   register_word = 16'h25_33;
            7'd64:   register_word = 16'h26_E3;
            7'd65:   register_word = 16'h9F_78;
            7'd66:   register_word = 16'hA0_68;
            7'd67:   register_word = 16'hA1_03;
            7'd68:   register_word = 16'hA6_D8;
            7'd69:   register_word = 16'hA7_D8;
            7'd70:   register_word = 16'hA8_F0;
            7'd71:   register_word = 16'hA9_90;
            7'd72:   register_word = 16'hAA_94;
            7'd73:   register_word = 16'h13_E7;
            7'd74:   register_word = 16'h69_07;
            default: register_word = 16'hFF_FF;
        endcase
    endfunction

    always_comb begin : register_table
        {sccb_reg_addr, sccb_reg_data} = register_word(init_index);
    end

    always_ff @(posedge clk_100MHz or posedge rst) begin : init_fsm
        if (rst) begin
            state       <= S_POWERUP_WAIT;
            delay_count <= '0;
            sccb_start  <= 1'b0;
            init_done   <= 1'b0;
            init_index  <= 7'd0;
        end else begin
            sccb_start <= 1'b0;

            case (state)
                S_POWERUP_WAIT: begin
                    if (delay_count == STARTUP_DELAY_CYCLES - 1) begin
                        delay_count <= '0;
                        state       <= S_ISSUE_WRITE;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                S_ISSUE_WRITE: begin
                    if (!sccb_busy) begin
                        sccb_start <= 1'b1;
                        state      <= S_WAIT_WRITE;
                    end
                end

                S_WAIT_WRITE: begin
                    if (sccb_done) begin
                        if (init_index == 7'd0) begin
                            delay_count <= '0;
                            state       <= S_RESET_WAIT;
                        end else begin
                            state <= S_NEXT_REGISTER;
                        end
                    end
                end

                S_RESET_WAIT: begin
                    if (delay_count == RESET_DELAY_CYCLES - 1) begin
                        delay_count <= '0;
                        state       <= S_NEXT_REGISTER;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                S_NEXT_REGISTER: begin
                    if (init_index == REG_COUNT - 1) begin
                        init_done <= 1'b1;
                        state     <= S_DONE;
                    end else begin
                        init_index <= init_index + 1'b1;
                        state      <= S_ISSUE_WRITE;
                    end
                end

                S_DONE: begin
                    init_done <= 1'b1;
                end

                default: begin
                    state <= S_POWERUP_WAIT;
                end
            endcase
        end
    end

endmodule
