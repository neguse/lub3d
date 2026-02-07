@echo off
setlocal enabledelayedexpansion

REM Run headless tests for all examples
REM Usage: scripts\run_tests.bat [build_dir] [num_frames]

set BUILD_DIR=%1
if "%BUILD_DIR%"=="" set BUILD_DIR=build\dummy-debug

set NUM_FRAMES=%2
if "%NUM_FRAMES%"=="" set NUM_FRAMES=10

set TEST_RUNNER=%BUILD_DIR%\lub3d-test.exe
if not exist "%TEST_RUNNER%" (
    echo Error: lub3d-test.exe not found in %BUILD_DIR%
    exit /b 1
)

echo Using test runner: %TEST_RUNNER%
echo Frames per test: %NUM_FRAMES%
echo.

set PASSED=0
set FAILED=0

REM Run all top-level examples (examples\foo.lua → examples.foo)
for %%s in (examples\*.lua) do (
    set BASENAME=%%~ns
    REM Skip model (crashes in dummy backend with shdc, needs investigation)
    if /i "!BASENAME!"=="model" (
        echo Skipped: %%s [dummy-backend issue]
    ) else (
        set MODNAME=examples.!BASENAME!
        echo ----------------------------------------
        echo Testing: !MODNAME!
        "%TEST_RUNNER%" "!MODNAME!" %NUM_FRAMES%
        set EC=!errorlevel!
        if !EC! equ 0 (
            set /a PASSED+=1
        ) else (
            echo FAILED with exit code: !EC!
            set /a FAILED+=1
        )
    )
)

REM Run subdirectory examples (examples\foo\init.lua → examples.foo)
for /d %%d in (examples\*) do (
    if exist "%%d\init.lua" (
        set DIRNAME=%%~nxd
        REM Skip rendering (asset-dependent, crashes without model files)
        if /i "!DIRNAME!"=="rendering" (
            echo Skipped: examples.!DIRNAME! [asset-dependent]
        ) else (
            set MODNAME=examples.!DIRNAME!
            echo ----------------------------------------
            echo Testing: !MODNAME!
            "%TEST_RUNNER%" "!MODNAME!" %NUM_FRAMES%
            set EC=!errorlevel!
            if !EC! equ 0 (
                set /a PASSED+=1
            ) else (
                echo FAILED with exit code: !EC!
                set /a FAILED+=1
            )
        )
    )
)

echo.
echo ========================================
echo Results: %PASSED% passed, %FAILED% failed
echo ========================================

if %FAILED% gtr 0 exit /b 1
exit /b 0
