English | [한국어](README.ko.md)

# Pan-Tilt Vision Tracker — FPGA-Based Manual and Automatic Object Tracking System

> This project was an assignment in the VGA class of the [Consortium] On-Device AI System Semiconductor Design (Cohort 2) program.

Team 1 (Doridori), 7 members · 2026.08.31~2026.09.08

| Member | Scope | Main Work |
|:--|:--|:--|
| Seongjae Jo (Lead) ([@seongjaejo](https://github.com/seongjaejo)) | Video noise filter | Schedule management, Line Buffer, 3×3 Window, majority decision |
| Jaewon Kwon ([@kw0njw2222](https://github.com/kw0njw2222)) | Joystick input processing | XADC configuration, X/Y separation, moving average, delta conversion, UART verification |
| Donghyun Kim ([@kimdh315](https://github.com/kimdh315)) | Video output and integration | Bounding Box overlay, VGA output, full Top integration |
| Yeonwoo Gim ([@mumallaeng](https://github.com/mumallaeng)) | Servo control | Auto/manual input selection, angle-to-PWM, `servo_top` integration |
| Gyeongmin Park ([@gyeongminbag27-arch](https://github.com/gyeongminbag27-arch)) | Video-to-motor interface | Coordinate error to angle conversion, angle accumulation, STM32 motor tests |
| Jongwoong Park ([@Critical-mankind](https://github.com/Critical-mankind)) | Video I/O and hardware | SCCB, camera initialization, color filter, 2-axis bracket assembly |
| Hoyeon Byeon ([@k948158](https://github.com/k948158)) | Object position calculation | min/max bounds, center coordinates, error from screen center |

![demo](https://github.com/user-attachments/assets/1f9c26d3-6eb8-4aac-a7ed-d1257c4be049)

# 1. Project Overview

## 1.1 Project Goal

This project detects a green object in the OV7670 camera image and makes a Pan-Tilt camera track it, using the error between the object center and the screen center. Video input, color detection, noise removal, center coordinate calculation, and servo motor control are integrated on a Basys3 FPGA. A manual mode lets the user steer the camera directly with a joystick.

In automatic mode, the two axis angles are updated so that the detected object stays at the center of the screen. In manual mode, the joystick X and Y analog inputs are converted by the XADC, smoothed, and passed to the motor controller as per-axis deltas. The VGA screen shows the camera image and the Bounding Box so the detection result can be checked.

## 1.2 Design Goals and Key Specifications

| Item | Design |
|:--|:--|
| FPGA and reference clock | Basys3, 100 MHz system clock |
| Camera input | OV7670, QVGA 320×240, RGB565 |
| VGA output | 640×480 timing, RGB444, 25 MHz pixel clock |
| Tracking target | Green object, G ≥ 128, G−R ≥ 40, G−B ≥ 40 |
| Spatial noise removal | Mask is 1 when 5 or more of the 9 pixels in a 3×3 neighborhood are detected |
| Valid object condition | 700 or more detected pixels in a frame |
| Coordinate smoothing | 5-frame average on the object center |
| Joystick processing | 12-bit ADC, 4-sample moving average, delta −10~+10 |
| Servo output | 2× SG90, 50 Hz, high pulse width about 1~2 ms |
| Mechanical range | Pan 15°\~165°, Tilt 25°\~155° |

The scope is color-based object detection and direction tracking of a single target. A recognition model that classifies object types, automatic threshold adjustment for lighting, and re-search after the target is lost are left as future improvements.

## 1.3 Schedule

Development was split into requirements and interface definition, module implementation, integration and verification, and hardware assembly and final demo. Video input and filters, joystick, and servo control were developed in parallel, with module signals and update conditions shared and connected at the Top.

| Period | Main Work | Deliverables |
|:--|:--|:--|
| 08.31~09.01 | Topic and requirements, block diagram and interface definition | WBS, system block diagram, interface spec |
| 09.01~09.04 | Camera, video filter, VGA, joystick, and servo modules with unit tests | Per-part RTL, testbenches |
| 09.02~09.04 | Full Top connection and interface adjustment | Top RTL, integration structure |
| 09.01~09.06 | Camera mount, 2-axis bracket, motor tests | Camera and servo hardware |
| 09.06~09.07 | Integrated simulation, FPGA tests, direction correction | Verification results, on-board checks |
| 09.08 | Final feature check, presentation and demo material | Slides, demo results |

## 1.4 Design and Development Environment

| Category | Environment and Use |
|:--|:--|
| Languages | SystemVerilog, Verilog / C for STM32 pre-tests |
| RTL design | FPGA design and simulation in Vivado |
| Verification | SystemVerilog testbenches, UVM, Synopsys VCS |
| Reference model | Python video Golden Model and result comparison |
| I/O devices | OV7670 camera, VGA monitor, HW-504 joystick, 2× SG90 servo |
| Auxiliary checks | Joystick data observed over UART, servo drive tests on STM32 |
| Collaboration and docs | Git, GitHub, WBS, interface spec, slides |

Each video processing stage was compared against a software reference model, and camera Capture and SCCB communication were verified with UVM. On the FPGA, both the screen output and the actual rotation direction of the motors were checked.

## 1.5 Roles and Components

| Member | Scope | Main Work |
|:--|:--|:--|
| Seongjae Jo ([@seongjaejo](https://github.com/seongjaejo)) | Team lead and video noise filter | Schedule management, Line Buffer, 3×3 Window, majority decision |
| Jaewon Kwon ([@kw0njw2222](https://github.com/kw0njw2222)) | Joystick input processing | XADC configuration, X/Y separation, moving average, delta conversion, UART verification |
| Donghyun Kim ([@kimdh315](https://github.com/kimdh315)) | Video output and integration | Bounding Box overlay, VGA output, full Top integration |
| Yeonwoo Gim ([@mumallaeng](https://github.com/mumallaeng)) | Servo control | Auto/manual input selection, angle-to-PWM, servo_top integration |
| Gyeongmin Park ([@gyeongminbag27-arch](https://github.com/gyeongminbag27-arch)) | Video-to-motor interface | Coordinate error to angle conversion, angle accumulation, STM32 motor tests |
| Jongwoong Park ([@Critical-mankind](https://github.com/Critical-mankind)) | Video I/O and hardware | SCCB, camera initialization, color filter, 2-axis bracket assembly |
| Hoyeon Byeon ([@k948158](https://github.com/k948158)) | Object position calculation | min/max bounds, center coordinates, error from screen center |

![](https://github.com/user-attachments/assets/4480b68b-50fc-43fa-8200-a9a4b6748380)

The FPGA handles video data processing and control signal generation. The camera and the joystick provide the inputs for automatic tracking and manual control, and the VGA monitor and the two servo motors output the detection and control results.

# 2. Theory and Background

## 2.1 Video Data and Color Detection

RGB565 represents one pixel in 16 bits, with 5 bits each for R and B and 6 bits for G. On the camera's 8-bit data bus, one pixel takes two transfers. For color comparison, each channel is expanded to an 8-bit range, and the brightness of one channel is compared together with its difference from the other channels.

A binary mask marks in 1 bit whether a pixel has the target color. A single detected point does not mean an object, so a majority vote over the surrounding 3×3 area reduces isolated pixels, and the detected pixel count over the whole frame decides whether the object is valid.

## 2.2 Bounding Box Based Center Calculation

A Bounding Box is the rectangle that encloses the object using the minimum and maximum X/Y coordinates of the detected pixels. In this design, the center is the average of the rectangle's two end points. This center differs from the centroid, which averages all detected pixel coordinates, and it is cheap to compute from the min/max values.

## 2.3 Moving Average and Input Smoothing

A moving average averages several recent inputs to soften sudden changes. The joystick ADC uses the last 4 samples, and the object center uses a 5-frame average. The two filters have different inputs and update periods; a longer window reduces more noise but also slows the response to new motion.

## 2.4 Pan-Tilt and PWM Control

Pan is the left-right rotation of the camera, and Tilt is the up-down rotation. The SG90 servo receives a PWM that repeats about every 20 ms, and the length of the high phase gives the target position. The controller turns the screen error or the joystick delta into an angle delta and accumulates it into the current command angle.

| Process | Input | Output |
|:--|:--|:--|
| Spatial filter | Neighboring pixels in one frame | Binary mask with reduced noise |
| Temporal average | Recent ADC samples or center coordinates | Smoothed input |
| Automatic tracking | Object error from the screen center | Pan/Tilt angle delta |
| Manual control | Joystick displacement from center | Control delta with direction and size |

# 3. System Architecture

## 3.1 Overall Structure

![](https://github.com/user-attachments/assets/f6b8cae3-4a86-406d-8df8-f68b15cffe12)

The system consists of the video path, the filter path, the joystick path, and the servo controller. OV7670 Capture assembles RGB565 pixels and stores them in the Frame Buffer, and the VGA path reads the display data from it. Green Filter, Noise Filter, and the Centroid block compute the object bounds and center error from the image.

The joystick path consists of the XADC, the X/Y Reader, the Noise Filter, and the Mapper. Automatic mode uses the error computed from the image, and manual mode selects the joystick delta. The selected input is converted to an angle in axis_ctrl and output as pwm_pan and pwm_tilt.

The Bounding Box is an output path for checking detection on screen, while servo control is a separate path that uses the center error. The key point of the Top integration is therefore to keep the display coordinates, the reference coordinates of the motor input, and their valid signals consistent.

## 3.2 Camera and VGA Connection Details

![](https://github.com/user-attachments/assets/a4403340-bea0-494d-8a89-115199d40700)

The SCCB Master and Register Init configure the camera, and the XCLK Generator supplies its reference clock. Capture stores pixels on the camera PCLK, and the VGA Core and Frame Reader read memory on the display pixel clock.

The Frame Buffer write address, write data, and write enable are connected as fb_waddr, fb_wdata, and fb_we. Read data is valid one clock after the requested address, so the Frame Reader delays the display-area and output-select signals by the same amount to align them with the RGB data.

The detailed block diagram above shows the early video I/O structure, where the color filter is labeled Red. The final tracker applies the Green Filter conditions to the same RGB565 input interface. The tracking target and the thresholds in this document are given for green.

## 3.3 Control Data Transfer

The video result carries the coordinates together with whether a target was detected and when the result was updated. When frame_valid is 0, the result is not accumulated as a new angle delta and the current angle is kept. Manual input is also passed at the valid time of new data so that the same value is not accumulated on every system clock.

## 3.4 Key Interfaces and Clocks

| Signal or Data | Width and Range | Connection and Valid Condition |
|:--|:--|:--|
| `cam_data` | 8 bit | OV7670 → Capture, received every PCLK while HREF is 1 |
| `fb_wdata` / `fb_waddr` | 16 bit / 17 bit | Capture → Frame Buffer, stored while `fb_we` is 1 |
| Image coordinates | X 9 bit / Y 8 bit | 320×240, X 0\~319 and Y 0\~239 |
| `clean_mask` / `out_valid` | 1 bit each | Noise Filter → bound calculation, valid with the coordinates |
| `rect_x` / `rect_y` | signed 9 bit / 8 bit | Error from the screen center, passed with the update and detection-valid conditions |
| `joy_motor_x/y` | −10~+10 | Signed delta, fits in 5 bits, sign-extended when connected to a wider input |
| `mode` / `manual_en` | 1 bit | 0 automatic, 1 manual |
| `angle_pan` / `angle_tilt` | 8 bit each | Current command angle, limited to the mechanical range |
| `pwm_pan` / `pwm_tilt` | 1 bit each | 50 Hz PWM to the two SG90s |

| Clock | Used By | Design Considerations |
|:--|:--|:--|
| System 100 MHz | SCCB, XADC control, servo control | Separate the angle update event from the PWM period |
| Camera PCLK | Capture and Frame Buffer write | Pixel reception driven by HREF and VSYNC |
| VGA 25 MHz | VGA timing, Frame Buffer read | Align output signals with the memory read latency |

The camera init-done level init_done passes through a 2-stage synchronizer in the PCLK domain and releases Capture. Unlike a single level signal, multi-bit coordinates and single pulses sent to another domain need both data hold and receive timing to be considered. In the final integration, the data and its update event are managed so that both refer to the same result.

# 4. Detailed Design

## 4.1 OV7670 Initialization and Capture

Camera initialization sends the address and data from the Register Table one after another as SCCB 3-byte writes. Each transfer consists of the device write address 0x42, the register address, and the register data. The FSM issues start when the master is not busy and sends the next register after done.

| Initialization Item | Setting and Behavior |
|:--|:--|
| Register Table | 75 entries for QVGA RGB565, index 0~74 |
| Startup delay | 1,000,000 cycles at 100 MHz = 10 ms |
| Reset delay | 500,000 cycles = 5 ms |
| SCCB SIOC | 100 kHz by default |
| SIOD | Driven low or released to High-Z |
| Ninth bit | Don't-Care with the default CHECK_ACK=0 |
| Capture start | Capture reset released after init_done is synchronized |

Capture receives two bytes while HREF is active and builds an RGB565 pixel as {high_byte, cam_data}. For each completed pixel, it asserts fb_we for one clock and stores the pixel in the Frame Buffer when the address is within 0~76,799. When VSYNC becomes active, the frame state, coordinates, and address are reset.

| Capture State | Role |
|:--|:--|
| `S_IDLE` | Initial state, ready to receive a frame |
| `S_WAIT_LINE` | Wait for the start of a valid line |
| `S_BYTE_HIGH` | Receive the RGB565 high byte |
| `S_BYTE_LOW` | Receive the low byte and assemble the pixel |
| `S_WAIT_LINE_END` | Wait for the end of the line and handle boundaries |

Besides normal frames, incomplete bytes, abnormal line lengths, and aborted frames were also verified. The boundary conditions were checked so that bad input does not carry over into the address or pixel assembly state of the next frame.

## 4.2 Green Filter

The Green Filter takes RGB565 pixels and outputs a binary mask for the pixels that meet the green condition. It splits RGB565 into R[15:11], G[10:5], and B[4:0], then expands them to R8, G8, and B8 by repeating the upper bits in the lower positions.

![](https://github.com/user-attachments/assets/c8820ca4-b3bc-476d-a5ba-b8f8f27d7b42)

| Item | Method |
|:--|:--|
| R expansion | 5-bit R followed by its upper 3 bits, 8 bits total |
| G expansion | 6-bit G followed by its upper 2 bits, 8 bits total |
| B expansion | 5-bit B followed by its upper 3 bits, 8 bits total |
| Green brightness | G8 ≥ 128 |
| Color dominance | G8 exceeds both R8 and B8 by 40 or more |
| Output | Mask 1 when the conditions hold, 0 otherwise |

An absolute brightness check alone would also include bright white and gray areas. The filter therefore also compares the difference from the other channels and selects pixels where green is relatively dominant. The mask valid is passed along with the valid of the RGB565 pixel.

This method needs only comparators and simple bit concatenation, but it depends on lighting and the camera color settings. Detection used fixed thresholds from indoor tests, and automatic correction for ambient brightness is left as a future improvement.

## 4.3 Line Buffer and 3×3 Noise Filter

A 3×3 majority filter removes isolated pixels from the color decision. Three rows are built from the current input line and the two previous lines, and the last three pixels of each row are kept in shift registers to form a 3×3 window.

![](https://github.com/user-attachments/assets/02f251e3-c8bf-4bb1-8113-a330b9a6967f)

When the sum of the 9 mask bits in the window is 5 or more, the output mask is 1. Even if the center input pixel is 0, the output can be 1 when most neighbors are 1. An isolated 1 is removed, which reduces the effect of small speckle noise on the object bound calculation.

| Design Element | Processing |
|:--|:--|
| Line storage | Provides the values at the same X position from the previous 1 and 2 rows |
| Window | Shifts the 3 rows, including the current one, into 3 columns |
| Majority rule | `clean_mask=1` when the sum of the 9 binary pixels is 5 or more |
| Boundary | Neighbors outside the image are treated as 0 |
| Output alignment | Mask is passed with its matching coordinates and valid |

The filter does not store the whole image and reuses line-sized storage. This memory saving applies inside the 3×3 filter and is separate from the Frame Buffer between the camera and VGA. The pipeline delay is also reflected so that the filter output coordinates stay aligned with the input coordinates.

## 4.4 Object Bounds and Center Error

min_max_find updates min_x, max_x, min_y, and max_y for pixels where clean_mask is 1 and the output is valid. When a frame has 700 or more valid pixels, target_valid is set, so small noise regions are not used as motor control input.

![](https://github.com/user-attachments/assets/c0ad7980-4373-42c8-819e-8a180d24660c)

The center coordinates are converted to a signed error relative to the QVGA screen center (160, 120). The X axis is negative toward the left of the screen, and the Y axis is positive toward the top when connected to the controller. The direction in which the image Y coordinate increases can differ from the actual Tilt rotation, so the direction was checked during integration.

A 5-frame average on the per-frame center keeps small changes at the object edge from causing repeated motor rotation. The coordinates and the detection valid are passed together when the frame result is final, and the angle is not updated when detection is not valid.

## 4.5 VGA Output and Bounding Box

The VGA Core uses 800 horizontal and 525 vertical counts at a 25 MHz pixel clock and outputs the image in the 640×480 area. The image itself is 320×240, so the full-screen display doubles both X and Y. The vertical refresh rate of this timing is about 59.5 Hz, which is 60 Hz class VGA output.

| Item | Rule |
|:--|:--|
| Source image coordinates | X 0\~319, Y 0\~239 |
| Display coordinates | X 0\~639, Y 0\~479 |
| Source address | `img_y × 320 + img_x` |
| Full-screen scaling | `img_x = vga_x >> 1`, `img_y = vga_y >> 1` |
| Sync signals | Active-low at horizontal 656\~751 and vertical 490\~491 |
| RGB output | Upper bits of RGB565 selected for RGB444 output |

![](https://github.com/user-attachments/assets/2d15b423-e6ff-4386-b809-105275de53d3)

draw_box compares the bound coordinates with the current output position and generates box_en where the box line is. The Frame Reader outputs red instead of the source color when box_en is set. The 1-clock read latency of the Frame Buffer and the delays of RGB and sync are matched so that the image and the box refer to the same position.

## 4.6 XADC Configuration and X/Y Separation

The joystick input reads the HW-504 X/Y voltages on XADC VAUX6 and VAUX14. The two channels are converted in sequence, so the reader has to know which axis each ADC result belongs to. xadc_xy_reader stores the channel address at the end of conversion and updates the matching axis register when the DRP read completes.

| Signal | When | Function |
|:--|:--|:--|
| channel_out[4:0] | eoc_out=1 | Stores the address of the converted channel |
| den_in | On eoc_out | Requests a DRP read of the result register |
| daddr_in[6:0] | On read request | Passes the result address for the channel |
| do_out[15:0] | drdy_out=1 | DRP read data, ADC value in [15:4] |
| VAUX6 / 5'h16 | Stored channel address match | Updates the 12-bit X register |
| VAUX14 / 5'h1E | Stored channel address match | Updates the 12-bit Y register |
| o_xadc_data_valid | After an X/Y pair update | Signals new input to the moving average filter |

### 4.6.1 EOC vs. DRDY

EOC marks the end of an analog conversion, and DRDY marks that the requested DRP read data is ready. The two signals mean different things, so the channel is identified at EOC and the value is stored at DRDY. This keeps the channel address and the read data matched.

### 4.6.2 Input Connection and Valid Signals

The P input of VAUX6 connects to JXADC pin 1 and the P input of VAUX14 to JXADC pin 2, with the N inputs referenced to GND. The joystick analog voltage is connected through a voltage divider. The collected X/Y values are handled as one valid pair so that the downstream logic never mixes values from different update times.

joystick_xadc_processor wraps the X/Y Reader and the Noise Filter and outputs filtered 12-bit X/Y values with o_filtered_data_valid. The Mapper computes a new control delta when that valid fires.

## 4.7 Joystick Moving Average and Delta Conversion

![](https://github.com/user-attachments/assets/0990d4ae-9d46-4887-a182-f46cced05f18)

xadc_noise_filter applies a moving average that divides the sum of the current ADC value and the previous three samples by 4. The X and Y axes are processed independently to reduce per-axis jitter, and the filter value is updated only when new X/Y data is valid.

Small ADC changes keep occurring at the joystick center, so a dead zone is used. Output is 0 in the center region, and input outside it is linearly mapped to a delta of −10~+10 using the measured range in each direction. The result is a direction and size used to update the current motor angle, not an absolute screen coordinate.

| Input State | Output Delta | Meaning in Manual Control |
|:--|:--|:--|
| Center dead zone | 0 | Keep the current angle |
| Left or down | Negative | Move that axis in the negative direction |
| Right or up | Positive | Move that axis in the positive direction |
| Near full deflection | −10 or +10 | Limited to the configured maximum delta |

The button input is debounced and toggled into manual_en. When manual_en=1 the manual input is selected, and when it is 0 the video tracking result is selected. Returning the joystick to center stops the camera instead of moving it back to the initial angle.

## 4.8 Mode Selection and Angle Accumulation

![](https://github.com/user-attachments/assets/90683f2f-1e3d-4f9c-9b4c-eb82ddafa83c)

- The main RTL consists of Axis Control and PWM Pan/Tilt.

- Axis Control takes the screen error in automatic mode or the joystick delta in manual mode, converts it to a limited angle, and PWM Pan/Tilt converts that angle to a PWM count.

- The servo runs at 50 Hz with a 20 ms period, and a high pulse of about 1\~2 ms maps to 0°\~180°. The target pulse width is updated at the period boundary.

The SG90 used here is a 5 V analog micro servo with an orange/yellow signal wire, red power, and brown GND. Its range is 0°\~180°, its size is about 23×29×12.2 mm, and it weighs about 9 g. On the actual bracket, only Pan 15°\~165° and Tilt 25°\~155° are used.

![](https://github.com/user-attachments/assets/ad439bb2-2186-494a-8168-5f84b095ed54)

Figure 7. SG90 servo specifications and the Pan/Tilt range used

Example PWM counts are about 100,000, 149,950, and 199,900 at the minimum, center, and maximum angles, producing a 1~2 ms high phase in proportion to the angle.

![](https://github.com/user-attachments/assets/b460e1e3-259b-4a31-8d87-0d5d47af3eea)

Figure 8. Servo position control by pulse width

- Pan is limited to 15°\~165° and Tilt to 25°\~155°, and each angle step is limited to ±20°.

Automatic and manual modes share the same axis control. A gain of 5/16° per count is applied to the input delta, each update is limited to ±20°, and the result is accumulated into the current angle.

ctrl_mode_mux selects either frame_dx/dy from automatic mode or joy_dx/dy from manual mode. Automatic mode updates on frame_done when the target detection is valid, and manual mode updates on joy_done. The selected input and its update signal are passed together to axis_ctrl.

![](https://github.com/user-attachments/assets/80653353-7231-4089-af08-ddfaf4505973)

A gain of 5/16° per count is applied to the input delta, and the angle applied in one step is limited to ±20°. The result is accumulated into the current angle and then clamped to the Pan and Tilt ranges. Based on the mounted bracket, Pan uses 15°\~165° and Tilt uses 25°\~155°.

## 4.9 PWM Generation and Servo Drive

![](https://github.com/user-attachments/assets/81da46e5-2c28-46a6-9393-773ae35be6c9)

servo_pwm converts the angle command into a high count and generates the PWM by comparing it with a 20 ms period counter. One period of the 100 MHz system clock is 10 ns, so a 20 ms PWM period is 2,000,000 counts. The target high count is applied at the PWM period boundary so the width of a pulse already being output does not change midway.

| Reference Angle | Nominal High Time | Nominal Count at 100 MHz |
|:--|:--|:--|
| 0° | 1.0 ms | 100,000 |
| 90° | 1.5 ms | 150,000 |
| 180° | 2.0 ms | 200,000 |

The actual command angle is limited to the Pan/Tilt range of the bracket.

### 4.9.1 Hardware Application

Two SG90s control the left-right and up-down direction of the camera. The motor signal, 5 V power, and GND were wired separately, and in the drive test stage STM32 TIM3 PWM was used to check the default position and the motion for command angle changes. The design was then integrated to use pwm_pan and pwm_tilt from the FPGA.

The servo pulse width is a command value and cannot be assumed to match the actual mechanical angle exactly. In the final integration, the mounting direction and end-stop interference were checked, and the angle limits and delta signs were set to match the actual assembly.

# 5. Verification

## 5.1 Verification Setup and Capture UVM

Verification was split into UVM verification of camera communication and pixel assembly, Python Golden Model comparison of the video pipeline, and before/after filter comparison of the joystick input. After checking the function and data match of each unit, the screen output and servo motion were checked on the FPGA.

![](https://github.com/user-attachments/assets/279b99f8-8ecf-46f1-8c28-106029cb58cd)

| Scenario | Checked |
|:--|:--|
| Normal 320×240 frame | Two-byte RGB565 assembly and matching store address |
| Short or long line | Handling of HREF periods outside the 320-pixel line |
| HREF ends during pixel assembly | Storage of an incomplete pixel and its effect on later lines |
| VSYNC or reset during reception | State and address reset, and recovery to normal reception |
| Store address out of range | Handling of the valid QVGA memory range |

The Capture scoreboard recorded PASS=78,203 and FAIL=0, and the presentation results list both UVM_ERROR and UVM_FATAL as 0. Functional coverage for Command and Write is 100% each.

The DUT entry on the coverage screen is 100%, while the top-level tb_top shows Score 99.60% and Line 97.62%. The top testbench and the DUT are different scopes, so the 100% result applies to the DUT and to the reviewed scope. The reviewed scope excludes unreachable X/Y conditions and unused upper counter bits.

## 5.2 SCCB Master UVM Verification

The SCCB Master was verified for 3-byte writes of device address, register address, and register data. Besides normal transfers, ACK/NACK input at each byte phase, start during a transfer, reset in every FSM state, and recovery from unused states were tested.

![](https://github.com/user-attachments/assets/868368f5-1eb7-4b6f-9760-a3ab255e9954)

| Item | Result |
|:--|:--|
| Scoreboard run log | PASS=56, FAIL=0 |
| UVM result | UVM_ERROR 0, UVM_FATAL 0 |
| Functional coverage | Address, Data, ACK/NACK, Busy Start, ACK Error 100% each |
| Code coverage | Line, Condition, Toggle, FSM, Branch, Assertion 100% each |
| Scope | Excludes the UVM library and recording helper code outside the DUT |

![](https://github.com/user-attachments/assets/9696a326-27d8-44a0-9e96-e5241840ba4b)

The reset scenarios checked that the master returns to its initial state even in the middle of a transfer. The ACK checks cover behavior under the ACK-check setting and were interpreted separately from the Ninth bit Don't-Care handling in the default camera initialization.

## 5.3 Video Pipeline Golden Model Verification

Video verification fed the same source data to a Python Golden Model and the RTL testbench and compared the result at each stage. Comparing only the final screen makes it hard to locate an error, so the Frame Buffer, color mask, noise filter, object bounds, and the error right before the servo input were checked separately.

![](https://github.com/user-attachments/assets/813b67ba-2271-4b57-982b-9dc689e08b13)

| Stage | Data Compared |
|:--|:--|
| Frame Buffer | Source RGB565 frame data |
| Green Color Filter | Binary mask from the color decision |
| Noise Filter | Binary mask after the 3×3 filter |
| Centroid Filter | Bounding Box and center result |
| Pre-servo input | dx, dy, and valid data |
| Final Display | Final display image with the Bounding Box |

Along with comparing the output images directly, the byte hashes of each result file were compared. Images can look alike while pixels or coordinates differ, so the RTL and Golden results of the same stage were checked to be bit-identical.

This verification covers the data from video input up to right before the servo input and the display result. The actual motor rotation and the mechanical response of the camera were checked separately on the FPGA.

## 5.4 Golden Model Comparison Results

![](https://github.com/user-attachments/assets/22a41259-6450-4b82-9a5b-44d3b5341a4a)

The green object in the source image becomes a white mask after the Green Filter, surrounding noise is reduced by the Noise Filter, and the final image shows a Bounding Box around the object. The Golden Model and the RTL show the same processing.

![](https://github.com/user-attachments/assets/855fa948-b990-4173-b2d3-f04fffb6fdcb)

![](https://github.com/user-attachments/assets/2d6b5621-7f16-467a-9633-23307253d6ea)

In the 320×240 and 640×480 comparison logs, all 6 stages show MATCH and TEST PASSED is printed. This means the byte results of the reference model and the RTL matched for that input image and test condition.

## 5.5 Joystick Filter Verification

For the joystick path, UART TX, a Data Sender, and a Debug Top were built so that the raw ADC value, the filter output, and the final delta could be checked stage by stage. These were used to compare the input jitter before and after filtering.

![](https://github.com/user-attachments/assets/28849a3d-5289-4219-91e6-88d5738d0d45)

In the graph, the moving-average output softens sudden large changes in the raw value. The presentation reports a peak-to-peak reduction of about 60%. This number is from the measured interval shown and does not mean the same reduction holds for every joystick position and speed.

Along with the filter, the dead zone and delta limit keep small ADC changes near the center from turning into unnecessary motor commands. On the other hand, the moving average adds response delay, so the filter length and input update period have to balance control feel and stability.

# 6. FPGA Implementation and Troubleshooting

## 6.1 FPGA Implementation and Demo Results

On the Basys3, real-time VGA output of the OV7670 image, the green object Bounding Box, automatic Pan/Tilt tracking, and manual joystick control were confirmed. The path from video input to servo output is integrated inside the FPGA.

<img width="400" alt="Automatic tracking and manual mode switching demo" src="https://github.com/user-attachments/assets/cedbc4c1-5a01-4269-8b3f-1adc2589df9d" />

In automatic mode, the camera rotated in the direction that reduces the error when the object center moved, and in manual mode the two axes moved independently with the X/Y joystick displacement. The GIF above is the second half of the demo video (Demo_Video_V1.mp4): the tracker switches from automatic to manual mode, is steered with the joystick, and then returns to automatic tracking.

The 4-sample ADC average and the 5-frame coordinate average reduce oscillation but add response delay. The averaging window and the angle gain have to be tuned for the trade-off between tracking speed and stability.

| Feature | Result |
|:--|:--|
| Camera output | OV7670 image shown on the VGA screen |
| Green object detection | Bounding Box shown from the color and noise filter result |
| Automatic tracking | Pan/Tilt control in the direction that reduces the center error |
| Manual control | Both axes steered by the X/Y joystick delta |
| Mode switching | Automatic or manual input selected by the button toggle |
| Angle limits | Commands generated within the mechanical Pan and Tilt ranges |

## 6.2 Root Cause Analysis

- The more the tracker corrected for the object, the further the camera moved in the opposite direction. The correction direction in image coordinates was opposite to the rotation direction of the servo as mounted on the bracket, so the sign of the angle delta was inverted to fix tracking.

| <img width="388" alt="Servo motion before the sign fix" src="https://github.com/user-attachments/assets/fa1862ec-282b-42ea-8878-01a27986d91f" /> | <img width="388" alt="Monitor view before the sign fix at 2x speed" src="https://github.com/user-attachments/assets/c6c05741-8759-4ac1-b214-02accd677d72" /> |
|:---:|:---:|

Figure 19. Behavior before the sign fix. Left: the servo turns away from the object. Right: the VGA screen in the same state (2x speed).

## 6.3 Improvements

- Adjust the color thresholds automatically for lighting changes, and add a Pan/Tilt re-search state when no object is detected.

- Apply a variable control gain based on the error size to reduce oscillation near the center and speed up the response to large moves.

# 7. Conclusion

This project integrated OV7670 video input, green object detection, center error calculation, VGA output, and Pan-Tilt servo control into one FPGA system. A manual joystick path was also built so that the same servo controller serves both automatic tracking and manual control.

| Target | Main Result |
|:--|:--|
| OV7670 Capture | Scoreboard 78,203 PASS, 0 FAIL |
| SCCB Master | Run log 56 PASS, 0 FAIL |
| Video Golden Model | 6 stages MATCH at 320×240 and 640×480 |
| Joystick moving average | About 60% peak-to-peak reduction in the measured interval |
| FPGA demo | Video and Bounding Box output, automatic tracking and manual control |

![](https://github.com/user-attachments/assets/31a2dfe2-39c4-4688-b637-1b72e6b38af2)

# References

- [1] Digilent, Basys 3 FPGA Board Reference Manual.
- [2] OmniVision, OV7670 CMOS VGA CameraChip Data Sheet.
- [3] TowerPro, SG90 Micro Servo Specification.
