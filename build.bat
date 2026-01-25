@echo off
setlocal enabledelayedexpansion

REM Build script for mane3d
REM Usage: build.bat [preset]
REM Example: build.bat win-d3d11-debug

set PRESET=%1
if "%PRESET%"=="" set PRESET=win-d3d11-debug

REM Find Visual Studio using vswhere
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath`) do set VS_PATH=%%i

if "%VS_PATH%"=="" (
    echo Error: Visual Studio not found
    exit /b 1
)

echo Found Visual Studio: %VS_PATH%

REM Setup environment
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
if errorlevel 1 (
    echo Error: Failed to setup VS environment
    exit /b 1
)

REM Configure and Build
echo Building preset: %PRESET%
cmake --preset %PRESET%
if errorlevel 1 exit /b %errorlevel%
cmake --build --preset %PRESET%

exit /b %errorlevel%
