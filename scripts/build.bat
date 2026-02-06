@echo off
setlocal enabledelayedexpansion

:: Find Visual Studio installation
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
    set "VS_PATH=%%i"
)

if not defined VS_PATH (
    echo Error: Visual Studio not found
    exit /b 1
)

:: Setup Visual Studio environment
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

:: Set UTF-8 for Python (needed for binding generation)
set PYTHONUTF8=1

:: Set CLANGPP/CLANG for binding generation
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Llvm.Clang -property installationPath`) do (
    set "CLANGPP=%%i\VC\Tools\Llvm\x64\bin\clang++.exe"
    set "CLANG=%%i\VC\Tools\Llvm\x64\bin\clang.exe"
)

:: Default preset
set "PRESET=win-d3d11-debug"
if not "%~1"=="" set "PRESET=%~1"

echo Building with preset: %PRESET%

:: Configure if needed
cmake --preset %PRESET%

:: Build
cmake --build --preset %PRESET%
