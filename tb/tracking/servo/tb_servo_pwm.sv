`timescale 1ns / 1ps

module tb_servo_pwm;

    logic       clk;
    logic       rst;
    logic [7:0] angle;  // 초기 각도 설정 (90도)
    logic       pwm;

    localparam time CLK_PERIOD = 20ns;  // 50MHz clock
    localparam int  PWM_PERIOD_CYCLES = 20ms / CLK_PERIOD;
    localparam int  PWM_MIN_CYCLES = 1ms / CLK_PERIOD;
    localparam int  PWM_RANGE_CYCLES = 1ms / CLK_PERIOD;
    localparam TOL = 2;  // 폭 측정 허용 오차 (클럭 단위)
    int error_count = 0;

    always #(CLK_PERIOD / 2) clk = ~clk;  // 50MHz clock

    servo_pwm dut (
        .clk  (clk),
        .rst  (rst),
        .angle(angle),
        .pwm  (pwm)
    );

    // high pulse width를 clock cycle 단위로 측정
    task automatic measure_pulse(output int width_cyc);
        time t_rise, t_fall;
        @(posedge pwm);
        t_rise = $time;
        @(negedge pwm);
        t_fall = $time;
        width_cyc = int'((t_fall - t_rise) / CLK_PERIOD);  // 펄스 폭을 클럭 사이클 단위로 변환
    endtask

    // 측정값과 기대값 비교
    task automatic check(input string name, input int got, input int exp);
        if (got < exp - TOL || got > exp + TOL) begin // 허용 오차 범위 밖이면 에러 카운트 증가
            $display("[%0t] ERROR: %s: got %0d, expected %0d", $time, name,
                     got, exp);
            error_count++;
        end else begin
            $display("[%0t] PASS: %s: got %0d, expected %0d", $time, name, got,
                     exp);
        end
    endtask

    // 각도에 따른 펄스 폭 측정 및 검증
    task automatic check_angle(input [7:0] angle_val, input int expected_width);
        int w;

        angle = angle_val;
        measure_pulse(w);
        @(posedge clk);
        check($sformatf("Angle %0d", angle_val), w, expected_width);
    endtask

    initial begin

        // reset 및 초기화
        clk   = 0;
        rst   = 1;
        angle = 8'd90;
        repeat (5) @(posedge clk);

        // PWM이 high 상태인지 확인
        if (pwm !== 1'b1) begin
            $display("[%0t] ERROR: PWM is not high (%0b)", $time, pwm);
            error_count++;
        end else $display("[%0t] PASS: PWM is high", $time);

        @(negedge clk);
        rst = 0;
        @(posedge clk);
        @(negedge pwm);
        @(posedge pwm);

        begin  // PWM period 측정
            time t0, t1;
            int per;
            @(posedge pwm);
            t0 = $time;
            @(posedge pwm);
            t1  = $time;
            per = int'((t1 - t0) / CLK_PERIOD);
            if (per != PWM_PERIOD_CYCLES) begin
                $error("[%0t] FAIL: PWM period is %0d cycles, expected %0d",
                       $time, per, PWM_PERIOD_CYCLES);
                error_count++;
            end else
                $display("[%0t] PASS: PWM period is %0d cycles", $time, per);
        end

        check_angle(8'd0, PWM_MIN_CYCLES);
        check_angle(8'd45,
                    PWM_MIN_CYCLES + (45 * PWM_RANGE_CYCLES) / 180);
        check_angle(8'd90,
                    PWM_MIN_CYCLES + (90 * PWM_RANGE_CYCLES) / 180);
        check_angle(8'd135,
                    PWM_MIN_CYCLES + (135 * PWM_RANGE_CYCLES) / 180);
        check_angle(8'd180,
                    PWM_MIN_CYCLES + (180 * PWM_RANGE_CYCLES) / 180);

        begin  // pulse 진행 중에 angle 변경 시, 다음 펄스에 반영되는지 확인
            int w;
            angle = 8'd0;
            measure_pulse(w);
            check("Angle 0", w, PWM_MIN_CYCLES);
            angle = 8'd180;  // 다음 펄스에 반영되어야 함
            measure_pulse(w);
            check("Angle 180", w,
                  PWM_MIN_CYCLES + (180 * PWM_RANGE_CYCLES) / 180);
        end

        if (error_count == 0) $display("[%0t] All PASSED!", $time);
        else $display("[%0t] %0d FAIL!", $time, error_count);
        $finish;
    end
endmodule
