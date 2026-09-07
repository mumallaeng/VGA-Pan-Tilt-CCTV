@echo off
rem ---------------------------------------------------------------------------
rem setup_env.bat  --  create a local Python venv for this folder and install
rem Pillow + numpy into it. Only png2ppm.py / ppm2png.py need Pillow; the core
rem flow (img2hex.py, gmodel.py, compare.py) is standard-library only and runs
rem on the system Python too.
rem
rem   setup_env.bat            create .venv and install
rem   setup_env.bat --force    delete and recreate .venv
rem ---------------------------------------------------------------------------
setlocal
cd /d %~dp0
set VENV=.venv

if /i "%~1"=="--force" (
    echo removing %VENV% ...
    rmdir /s /q %VENV% 2>nul
)

if exist %VENV%\Scripts\python.exe (
    echo venv already present: %VENV%
) else (
    echo creating venv %VENV% with "python -m venv" ...
    python -m venv %VENV%
    if errorlevel 1 (
        echo.
        echo   venv creation failed. Check that "python" on PATH is a real
        echo   CPython with venv support ^(python --version^).
        exit /b 1
    )
)

set PY=%VENV%\Scripts\python.exe
echo.
echo == upgrading pip ==
"%PY%" -m pip install --upgrade pip

echo.
echo == installing pillow + numpy ==
"%PY%" -m pip install pillow numpy
if errorlevel 1 (
    echo.
    echo   pip install failed. If this machine is behind a proxy, set
    echo   HTTP_PROXY / HTTPS_PROXY and retry, or install from local wheels:
    echo       "%PY%" -m pip install --no-index --find-links wheels pillow numpy
    exit /b 1
)

echo.
echo == verify ==
"%PY%" -c "import PIL, numpy; print('PIL', PIL.__version__, ' numpy', numpy.__version__)"
if errorlevel 1 exit /b 1

echo.
echo done.  run_remote.bat auto-detects %VENV% and uses it.
echo direct use:  "%PY%" png2ppm.py photo.png greenball_320x240.ppm
