@echo off
setlocal enabledelayedexpansion

REM Run headless tests for all examples
REM Usage: scripts\run_tests.bat [build_dir] [num_frames]

set BUILD_DIR=%1
if "%BUILD_DIR%"=="" set BUILD_DIR=build\dummy-debug

set NUM_FRAMES=%2
if "%NUM_FRAMES%"=="" set NUM_FRAMES=10

set TEST_RUNNER=%BUILD_DIR%\mane3d-test.exe
if not exist "%TEST_RUNNER%" (
    echo Error: mane3d-test.exe not found in %BUILD_DIR%
    exit /b 1
)

echo Using test runner: %TEST_RUNNER%
echo Frames per test: %NUM_FRAMES%
echo.

set PASSED=0
set FAILED=0

REM Note: rendering\init.lua excluded - requires assets\mill-scene which is gitignored
for %%s in (
    examples\main.lua
    examples\breakout.lua
    examples\raytracer.lua
    examples\lighting.lua
    examples\triangle.lua
    examples\hakonotaiatari\init.lua
) do (
    if exist "%%s" (
        echo ----------------------------------------
        echo Testing: %%s
        "%TEST_RUNNER%" "%%s" %NUM_FRAMES%
        set EC=!errorlevel!
        if !EC! equ 0 (
            set /a PASSED+=1
        ) else (
            echo FAILED with exit code: !EC!
            set /a FAILED+=1
        )
    ) else (
        echo Skipped: %%s
    )
)

echo.
echo ========================================
echo Results: %PASSED% passed, %FAILED% failed
echo ========================================

if %FAILED% gtr 0 exit /b 1
exit /b 0
