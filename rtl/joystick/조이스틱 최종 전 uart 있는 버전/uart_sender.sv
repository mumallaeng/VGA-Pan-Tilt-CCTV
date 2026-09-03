`timescale 1ns / 1ps

module uart_sender(
    input  logic               clk,
    input  logic               rst,
    input  logic               i_sender_start,
    input  logic        [11:0] i_raw_x,
    input  logic        [11:0] i_raw_y,

    input  logic        [11:0] i_filtered_x,
    input  logic        [11:0] i_filtered_y,

    input  logic signed [ 4:0] i_joy_motor_x,
    input  logic signed [ 4:0] i_joy_motor_y,
    input  logic               i_manual_en,

    input  logic               i_tx_busy,
    output logic        [ 7:0] o_tx_data,
    output logic               o_tx_start,
    output logic               o_sender_busy
);

    localparam logic [5:0] LAST_INDEX = 6'd38;

    typedef enum logic [1:0] { 
        IDLE = 2'd0,
        SEND = 2'd1,
        BUSY = 2'd2,
        DONE = 2'd3
    } state_e;

    state_e state;

    logic [5:0] index;

    // UART 한 줄 전송 중 값이 변하지 않도록 저장
    logic [11:0] snap_raw_x;
    logic [11:0] snap_raw_y;
    logic [11:0] snap_filtered_x;
    logic [11:0] snap_filtered_y;
    logic        snap_motor_x_negative;
    logic [ 8:0] snap_motor_x_magnitude;
    logic        snap_motor_y_negative;
    logic [ 7:0] snap_motor_y_magnitude;
    logic        snap_manual_en;

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            state                    <= IDLE;
            index               <= 6'd0;
            snap_raw_x               <= 12'd0;
            snap_raw_y               <= 12'd0;
            snap_filtered_x          <= 12'd0;
            snap_filtered_y          <= 12'd0;
            snap_motor_x_negative    <= 1'b0;
            snap_motor_x_magnitude   <= 9'd0;
            snap_motor_y_negative    <= 1'b0;
            snap_motor_y_magnitude   <= 8'd0;
            snap_manual_en           <= 1'b0;
            o_tx_data                <= 8'h00;
            o_tx_start               <= 1'b0;
            o_sender_busy            <= 1'b0;
            
        end else begin
            o_tx_start <= 1'b0;
            case (state)
                IDLE: begin
                    o_sender_busy <= 1'b0;

                    if (i_sender_start) begin
                        // 한 줄에 사용할 값들을 동시에 저장
                        snap_raw_x      <= i_raw_x;
                        snap_raw_y      <= i_raw_y;
                        snap_filtered_x <= i_filtered_x;
                        snap_filtered_y <= i_filtered_y;
                        snap_manual_en  <= i_manual_en;

                        // Motor X의 부호와 절댓값 저장
                        if (i_joy_motor_x < 0) begin
                            snap_motor_x_negative  <= 1'b1;
                            snap_motor_x_magnitude <= -i_joy_motor_x;
                        end else begin
                            snap_motor_x_negative  <= 1'b0;
                            snap_motor_x_magnitude <= i_joy_motor_x;
                        end

                        // Motor Y의 부호와 절댓값 저장
                        if (i_joy_motor_y < 0) begin
                            snap_motor_y_negative  <= 1'b1;
                            snap_motor_y_magnitude <= -i_joy_motor_y;
                        end else begin
                            snap_motor_y_negative  <= 1'b0;
                            snap_motor_y_magnitude <= i_joy_motor_y;
                        end

                        index         <= 6'd0;
                        o_sender_busy <= 1'b1;
                        state         <= SEND;
                    end
                end
                SEND: begin
                    // UART TX가 IDLE일 때 한 문자 전달
                    if (!i_tx_busy) begin
                        case (index)
                            6'd0 : o_tx_data <= "R";
                            6'd1 : o_tx_data <= ":";
                            6'd2 : o_tx_data <= 8'h30 + ((snap_raw_x / 1000) % 10);
                            6'd3 : o_tx_data <= 8'h30 + ((snap_raw_x / 100) % 10);
                            6'd4 : o_tx_data <= 8'h30 + ((snap_raw_x / 10) % 10);
                            6'd5 : o_tx_data <= 8'h30 + (snap_raw_x % 10);
                            6'd6 : o_tx_data <= ",";
                            6'd7 : o_tx_data <= 8'h30 + ((snap_raw_y / 1000) % 10);
                            6'd8 : o_tx_data <= 8'h30 + ((snap_raw_y / 100) % 10);
                            6'd9 : o_tx_data <= 8'h30 + ((snap_raw_y / 10) % 10);
                            6'd10: o_tx_data <= 8'h30 + (snap_raw_y % 10);
                            6'd11: o_tx_data <= " ";
                            6'd12: o_tx_data <= "F";
                            6'd13: o_tx_data <= ":";
                            6'd14: o_tx_data <= 8'h30 + ((snap_filtered_x / 1000) % 10);
                            6'd15: o_tx_data <= 8'h30 + ((snap_filtered_x / 100) % 10);
                            6'd16: o_tx_data <= 8'h30 + ((snap_filtered_x / 10) % 10);
                            6'd17: o_tx_data <= 8'h30 + (snap_filtered_x % 10);
                            6'd18: o_tx_data <= ",";
                            6'd19: o_tx_data <= 8'h30 + ((snap_filtered_y / 1000) % 10);
                            6'd20: o_tx_data <= 8'h30 + ((snap_filtered_y / 100) % 10);
                            6'd21: o_tx_data <= 8'h30 + ((snap_filtered_y / 10) % 10);
                            6'd22: o_tx_data <= 8'h30 + (snap_filtered_y % 10);
                            6'd23: o_tx_data <= " ";
                            6'd24: o_tx_data <= "M";
                            6'd25: o_tx_data <= ":";
                            6'd26: o_tx_data <= snap_motor_x_negative ? "-" : "+";
                            6'd27: o_tx_data <= 8'h30 + ((snap_motor_x_magnitude / 100) % 10);
                            6'd28: o_tx_data <= 8'h30 + ((snap_motor_x_magnitude / 10) % 10);
                            6'd29: o_tx_data <= 8'h30 + (snap_motor_x_magnitude % 10);
                            6'd30: o_tx_data <= ",";
                            6'd31: o_tx_data <= snap_motor_y_negative ? "-" : "+";
                            6'd32: o_tx_data <= 8'h30 + ((snap_motor_y_magnitude / 100) % 10);
                            6'd33: o_tx_data <= 8'h30 + ((snap_motor_y_magnitude / 10) % 10);
                            6'd34: o_tx_data <= 8'h30 + (snap_motor_y_magnitude % 10);
                            6'd35: o_tx_data <= ",";
                            6'd36: o_tx_data <= snap_manual_en ? "1" : "0";
                            // CR + LF
                            6'd37: o_tx_data <= 8'h0D; // 커서 맨앞으로
                            6'd38: o_tx_data <= 8'h0A; // 커서 다음줄로
                            default: o_tx_data <= " ";
                        endcase
                        // 선택한 문자 한 개의 전송 요청
                        o_tx_start <= 1'b1;
                        state      <= BUSY;
                    end
                end
                BUSY: begin
                    // uart_tx가 tx_start를 받아 tx_busy를 1로 올렸는지 확인
                    if (i_tx_busy)
                        state <= DONE;
                end
                DONE: begin
                    // 한 문자 전송이 끝나 tx_busy가 0이 되기를 기다림
                    if (!i_tx_busy) begin
                        if (index == LAST_INDEX) begin
                            o_sender_busy <= 1'b0;
                            state         <= IDLE;
                        end else begin
                            index <= index + 1'b1;
                            state      <= SEND;
                        end
                    end
                end
                default: begin
                    state         <= IDLE;
                    index         <= 6'd0;
                    o_sender_busy <= 1'b0;
                end
            endcase   
        end
    end
endmodule