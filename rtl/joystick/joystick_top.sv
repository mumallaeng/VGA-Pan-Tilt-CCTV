`timescale 1ns / 1ps

module joystick_top (
    input logic clk,
    input logic rst,
    input logic vauxp6,
    input logic vauxn6,
    input logic vauxp14,
    input logic vauxn14,
    input logic joy_btn,
    //output logic [8:0] motor_x,
    //output logic [7:0] motor_y,
    output logic       manual_en
);

    logic [ 4:0] xadc_channel;
    logic [15:0] xadc_out_data;
    logic        xadc_eoc;
    logic        xadc_drdy;
    logic        xadc_alarm;
    logic        xadc_eos;
    logic        xadc_busy;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            manual_en <= 1'b0;       // 0: 자동 모드
        end else if (btn_pulse) begin
            manual_en <= ~manual_en; // 누를 때마다 토글
        end
    end

    button_debounce U_BTN_DEBOUNCE (
        .clk  (clk),
        .rst  (rst),
        .i_btn(~joy_btn),
        .o_btn(btn_pulse)
    );

    xadc_wiz_0 U_XADC (
        .dclk_in    (clk),
        .reset_in   (rst),
        .vauxp6     (vauxp6),
        .vauxn6     (vauxn6),
        .vauxp14    (vauxp14),
        .vauxn14    (vauxn14),
        .channel_out(xadc_channel),
        .do_out     (xadc_out_data),
        .drdy_out   (xadc_drdy),
        .di_in      (16'd0),
        .daddr_in   ({2'b00, xadc_channel}),
        .eoc_out    (xadc_eoc),
        .den_in     (xadc_eoc),
        .dwe_in     (1'b0),
        // 미사용 포트      
        .vp_in      (1'b0),
        .vn_in      (1'b0),
        .alarm_out  (xadc_alarm),
        .eos_out    (xadc_eos),
        .busy_out   (xadc_busy)
    );

    (* mark_debug = "true" *) logic [11:0] w_filtered_x;
    (* mark_debug = "true" *) logic [11:0] w_filtered_y;
    (* mark_debug = "true" *) logic w_filtered_data_valid;

    joystick_xadc_processor U_JOYSTICK_XADC_PROCESSOR (
        .clk                  (clk),
        .rst                  (rst),
        .channel_addr         (xadc_channel),
        .xadc_data            (xadc_out_data[15:4]),
        .xadc_drdy            (xadc_drdy),
        .xadc_eoc             (xadc_eoc),
        .o_filtered_x         (w_filtered_x),
        .o_filtered_y         (w_filtered_y),
        .o_filtered_data_valid(w_filtered_data_valid)
    );
    
endmodule
