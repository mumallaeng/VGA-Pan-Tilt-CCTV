@echo off
rem Remote (Vivado 2020.2 xsim) bit-exact equivalence run.
rem Runs BOTH display modes and tags every artifact:
rem   FULLSCREEN 2x (vga_sw=01)  -> *_640x480.*
rem   ORIGINAL 1:1  (vga_sw=00)  -> *_320x240.*
rem   run_remote.bat [image]   320x240 .ppm, or any image if .venv has PIL, or omit
rem Run from a shell where the Vivado 2020.2 tools are on PATH
rem   (call C:\Xilinx\Vivado\2020.2\settings64.bat first).
setlocal enabledelayedexpansion
cd /d %~dp0

set RTL=..\..\rtl
if not exist _work mkdir _work

set PY=python
if exist .venv\Scripts\python.exe set PY=.venv\Scripts\python.exe
echo using python: %PY%

rem default input: the official demo photo if present, else a synthetic frame
set SRC_ARG=%~1
if "%SRC_ARG%"=="" if exist golden_test_sample_img.png set SRC_ARG=golden_test_sample_img.png

if "%SRC_ARG%"=="" (
    "%PY%" make_synth_ppm.py _work/src_320x240.ppm || exit /b 1
    set SRC_PPM=_work/src_320x240.ppm
) else if /i "!SRC_ARG:~-4!"==".ppm" (
    set SRC_PPM=!SRC_ARG!
) else (
    "%PY%" png2ppm.py "!SRC_ARG!" _work/src_320x240.ppm || exit /b 1
    set SRC_PPM=_work/src_320x240.ppm
)
"%PY%" img2hex.py "!SRC_PPM!" _work/src.hex || exit /b 1

echo == xvlog / xelab ==
call xvlog -sv -nolog ^
    tb_top_video_golden.sv ^
    %RTL%\video\vga_frame_reader_v4.sv ^
    %RTL%\video\draw_box.sv ^
    %RTL%\common\filter\green_color_filter.sv ^
    %RTL%\common\filter\noise_filter_3x3.sv ^
    %RTL%\common\filter\line_buffer.sv ^
    %RTL%\common\filter\centroid_filter.sv ^
    %RTL%\common\filter\bounding_box.sv ^
    %RTL%\common\filter\object_center.sv ^
    %RTL%\common\filter\center_error.sv || exit /b 1
call xelab -nolog tb_top_video_golden -s tb_sim || exit /b 1

call :run 1 0 640x480
call :run 1 1 640x480_raw
call :run 0 0 320x240
goto :done

:run
set FS=%1
set RAW=%2
set TAG=%3
echo.
echo =================  %TAG%  (FS=%FS% RAW=%RAW%)  =================
rem NOTE: forward slashes in plusarg values -- xsim treats '\' as an escape.
call xsim tb_sim -nolog -runall ^
    -testplusarg "HEX=_work/src.hex" -testplusarg "OUT=_work" ^
    -testplusarg "FS=%FS%" -testplusarg "RAW=%RAW%" || exit /b 1
"%PY%" gmodel.py _work/src.hex _work %FS% %TAG% %RAW% || exit /b 1
"%PY%" compare.py _work %TAG%
goto :eof

:done
echo.
echo == render PNGs ==
"%PY%" render_images.py _work
echo.
echo all done. _work\ has, per config tag (640x480 / 640x480_raw / 320x240):
echo   golden_green_*/rtl_green_*   golden_clean_*/rtl_clean_*   golden_out_*/rtl_out_*
echo   (.pgm/.ppm = data for compare.py ; .png = viewable ; golden_=SW model, rtl_=SV)
