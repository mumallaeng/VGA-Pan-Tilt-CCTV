`timescale 1ns / 1ps

// Streams the whole servo control path out of the 9600 baud debug UART as one
// human readable ASCII line per sampled frame:
//
//   dx=+040 dy=-010 v=1 n=006 ax=+040 ay=-010 pan=093 tlt=090<CR><LF> 59 bytes
//
// The fields follow the signal chain, so one line shows an input and what the
// controller did with it:
//
//   dx,dy    centroid_filter output: object offset from the screen centre in
//            pixels. dx > 0 is RIGHT of centre, dy > 0 is ABOVE centre.
//   v        frame_valid: 1 = this frame found a target. 0 = it did not, and
//            dx/dy are the last valid position centroid_filter is still
//            holding, so the digits are stale rather than meaningless.
//   n        frame_done pulses counted so far, modulo 1000. Its level cannot
//            be reported directly because frame_done is what triggers the
//            sample, so it always reads 1 at that instant. The count is the
//            useful form: consecutive lines must differ by exactly DECIMATION.
//            A larger gap means a sample was dropped because the previous line
//            was still going out; a frozen count means frames stopped.
//   ax,ay    ctrl_mode_mux output, i.e. what axis_ctrl was actually fed. In
//            AUTO mode this equals dx/dy; in MANUAL it is the scaled joystick,
//            so comparing the two pairs shows which source the mux picked.
//   pan,tlt  axis_ctrl output angles in degrees (0..180) driving servo_pwm.
//
// A line goes out on every sampled frame whether or not a target was found, so
// the link never goes silent and a quiet terminal always means a real problem.
//
// frame_done is produced in the vga_pclk (25 MHz) domain while this block runs
// on clk (100 MHz), so its pulse is visible here for four clk cycles. It is
// edge detected rather than used as a level, otherwise one frame would queue
// four lines. centroid_filter holds its value after the pulse (rect_x_hold),
// so sampling at the edge is safe.
//
// Bandwidth: 9600 baud 8N1 = 960 byte/s, so one 59 byte line takes 61.5 ms
// against a 16.7 ms frame period. DECIMATION must be at least 4; the default 6
// gives a 100 ms sample interval (~10 lines/s, 590 byte/s) with margin.
module servo_debug_uart #(
    parameter integer DECIMATION = 6
) (
    input  logic              clk,          // 100 MHz
    input  logic              rst,
    input  logic signed [9:0] frame_dx,     // vga_pclk domain
    input  logic signed [8:0] frame_dy,
    input  logic              frame_valid,
    input  logic              frame_done,
    input  logic signed [9:0] delta_x,      // ctrl_mode_mux output
    input  logic signed [8:0] delta_y,
    input  logic        [7:0] pan_angle,    // axis_ctrl output
    input  logic        [7:0] tilt_angle,
    output logic              tx
);

    localparam integer LINE_BYTES = 59;
    localparam integer DEC_WIDTH = (DECIMATION <= 1) ? 1 : $clog2(DECIMATION);

    // vga_pclk -> clk: turn the stretched level into a single clk event.
    // frame_done alone, so frames without a target still report.
    logic frame_req, frame_req_d, frame_pulse;
    assign frame_req   = frame_done;
    assign frame_pulse = frame_req & ~frame_req_d;

    logic [DEC_WIDTH-1:0] dec_counter;
    logic                 dec_hit;
    logic                 sample_now;
    assign dec_hit    = (DECIMATION <= 1) || (dec_counter == DECIMATION - 1);
    assign sample_now = frame_pulse & dec_hit;

    // Every frame_done pulse is counted, including the ones decimation skips
    // and the ones dropped while a line was going out, so the printed gap
    // between lines tells those two cases apart.
    logic [9:0] frame_cnt;

    // Sign and magnitude, split at capture time. Widening by one bit first
    // keeps negating the most negative input from overflowing.
    logic signed [10:0] dx_ext, dy_ext, ax_ext, ay_ext;
    logic        [10:0] dx_mag, dy_mag, ax_mag, ay_mag;
    assign dx_ext = frame_dx;
    assign dy_ext = frame_dy;
    assign ax_ext = delta_x;
    assign ay_ext = delta_y;
    assign dx_mag = dx_ext[10] ? (-dx_ext) : dx_ext;
    assign dy_mag = dy_ext[10] ? (-dy_ext) : dy_ext;
    assign ax_mag = ax_ext[10] ? (-ax_ext) : ax_ext;
    assign ay_mag = ay_ext[10] ? (-ay_ext) : ay_ext;

    logic        snap_valid;
    logic        snap_dx_neg, snap_dy_neg, snap_ax_neg, snap_ay_neg;
    logic [10:0] snap_dx_mag, snap_dy_mag, snap_ax_mag, snap_ay_mag;
    logic [10:0] snap_pan, snap_tilt, snap_frame_cnt;

    // Divisors are constants, so these synthesise to a little LUT logic
    // rather than a divider.
    function automatic logic [7:0] digit_ascii(input logic [10:0] mag,
                                               input logic [1:0] place);
        logic [10:0] d;
        begin
            case (place)
                2'd2:    d = mag / 11'd100;            // hundreds
                2'd1:    d = (mag / 11'd10) % 11'd10;  // tens
                default: d = mag % 11'd10;             // ones
            endcase
            digit_ascii = 8'h30 + d[3:0];
        end
    endfunction

    typedef enum logic [1:0] {
        IDLE,
        SEND,
        WAIT_BUSY,
        WAIT_DONE
    } state_t;

    state_t     state;
    logic [5:0] byte_idx;
    logic       tx_start;
    logic       tx_busy;
    logic [7:0] tx_data;

    always_comb begin
        case (byte_idx)
            6'd0:    tx_data = "d";
            6'd1:    tx_data = "x";
            6'd2:    tx_data = "=";
            6'd3:    tx_data = snap_dx_neg ? "-" : "+";
            6'd4:    tx_data = digit_ascii(snap_dx_mag, 2'd2);
            6'd5:    tx_data = digit_ascii(snap_dx_mag, 2'd1);
            6'd6:    tx_data = digit_ascii(snap_dx_mag, 2'd0);
            6'd7:    tx_data = " ";

            6'd8:    tx_data = "d";
            6'd9:    tx_data = "y";
            6'd10:   tx_data = "=";
            6'd11:   tx_data = snap_dy_neg ? "-" : "+";
            6'd12:   tx_data = digit_ascii(snap_dy_mag, 2'd2);
            6'd13:   tx_data = digit_ascii(snap_dy_mag, 2'd1);
            6'd14:   tx_data = digit_ascii(snap_dy_mag, 2'd0);
            6'd15:   tx_data = " ";

            6'd16:   tx_data = "v";
            6'd17:   tx_data = "=";
            6'd18:   tx_data = snap_valid ? "1" : "0";
            6'd19:   tx_data = " ";

            6'd20:   tx_data = "n";
            6'd21:   tx_data = "=";
            6'd22:   tx_data = digit_ascii(snap_frame_cnt, 2'd2);
            6'd23:   tx_data = digit_ascii(snap_frame_cnt, 2'd1);
            6'd24:   tx_data = digit_ascii(snap_frame_cnt, 2'd0);
            6'd25:   tx_data = " ";

            6'd26:   tx_data = "a";
            6'd27:   tx_data = "x";
            6'd28:   tx_data = "=";
            6'd29:   tx_data = snap_ax_neg ? "-" : "+";
            6'd30:   tx_data = digit_ascii(snap_ax_mag, 2'd2);
            6'd31:   tx_data = digit_ascii(snap_ax_mag, 2'd1);
            6'd32:   tx_data = digit_ascii(snap_ax_mag, 2'd0);
            6'd33:   tx_data = " ";

            6'd34:   tx_data = "a";
            6'd35:   tx_data = "y";
            6'd36:   tx_data = "=";
            6'd37:   tx_data = snap_ay_neg ? "-" : "+";
            6'd38:   tx_data = digit_ascii(snap_ay_mag, 2'd2);
            6'd39:   tx_data = digit_ascii(snap_ay_mag, 2'd1);
            6'd40:   tx_data = digit_ascii(snap_ay_mag, 2'd0);
            6'd41:   tx_data = " ";

            6'd42:   tx_data = "p";
            6'd43:   tx_data = "a";
            6'd44:   tx_data = "n";
            6'd45:   tx_data = "=";
            6'd46:   tx_data = digit_ascii(snap_pan, 2'd2);
            6'd47:   tx_data = digit_ascii(snap_pan, 2'd1);
            6'd48:   tx_data = digit_ascii(snap_pan, 2'd0);
            6'd49:   tx_data = " ";

            6'd50:   tx_data = "t";
            6'd51:   tx_data = "l";
            6'd52:   tx_data = "t";
            6'd53:   tx_data = "=";
            6'd54:   tx_data = digit_ascii(snap_tilt, 2'd2);
            6'd55:   tx_data = digit_ascii(snap_tilt, 2'd1);
            6'd56:   tx_data = digit_ascii(snap_tilt, 2'd0);

            6'd57:   tx_data = 8'h0D;  // CR
            default: tx_data = 8'h0A;  // LF
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_req_d <= 1'b0;
            dec_counter <= '0;
            snap_valid  <= 1'b0;
            snap_dx_neg <= 1'b0;
            snap_dy_neg <= 1'b0;
            snap_ax_neg <= 1'b0;
            snap_ay_neg <= 1'b0;
            snap_dx_mag <= '0;
            snap_dy_mag <= '0;
            snap_ax_mag <= '0;
            snap_ay_mag <= '0;
            snap_pan    <= '0;
            snap_tilt   <= '0;
            frame_cnt      <= '0;
            snap_frame_cnt <= '0;
            state       <= IDLE;
            byte_idx    <= '0;
            tx_start    <= 1'b0;
        end else begin
            frame_req_d <= frame_req;
            tx_start    <= 1'b0;

            if (frame_pulse) begin
                if (dec_hit) dec_counter <= '0;
                else dec_counter <= dec_counter + 1'b1;

                // Wrap at 1000 so the three printed digits are exact.
                if (frame_cnt == 10'd999) frame_cnt <= '0;
                else frame_cnt <= frame_cnt + 1'b1;
            end

            case (state)
                IDLE: begin
                    // A sample that lands mid-line is dropped. Buffering it
                    // would only add latency to the behaviour being observed.
                    if (sample_now) begin
                        snap_valid  <= frame_valid;
                        snap_dx_neg <= dx_ext[10];
                        snap_dy_neg <= dy_ext[10];
                        snap_ax_neg <= ax_ext[10];
                        snap_ay_neg <= ay_ext[10];
                        snap_dx_mag <= dx_mag;
                        snap_dy_mag <= dy_mag;
                        snap_ax_mag <= ax_mag;
                        snap_ay_mag <= ay_mag;
                        snap_pan    <= {3'b0, pan_angle};
                        snap_tilt   <= {3'b0, tilt_angle};
                        snap_frame_cnt <= {1'b0, frame_cnt};
                        byte_idx    <= '0;
                        state       <= SEND;
                    end
                end

                // uart_tx samples tx_start as a level while it sits in IDLE,
                // so it must be a single pulse followed by a tx_busy
                // handshake, otherwise the same byte repeats forever.
                SEND: begin
                    tx_start <= 1'b1;
                    state    <= WAIT_BUSY;
                end

                WAIT_BUSY: begin
                    if (tx_busy) state <= WAIT_DONE;
                end

                WAIT_DONE: begin
                    if (!tx_busy) begin
                        if (byte_idx == LINE_BYTES - 1) begin
                            state <= IDLE;
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                            state    <= SEND;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    uart U_DEBUG_UART (
        .clk     (clk),
        .rst     (rst),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .rx      (1'b1),      // transmit-only debug link
        .rx_data (),
        .rx_done (),
        .tx_busy (tx_busy),
        .tx      (tx)
    );

endmodule
