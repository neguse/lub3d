@echo off
setlocal enabledelayedexpansion

:: Set UTF-8 encoding for Python
set PYTHONUTF8=1

:: Find Visual Studio installation with LLVM/Clang
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Llvm.Clang -property installationPath`) do (
    set "VS_PATH=%%i"
)

if not defined VS_PATH (
    echo Error: Visual Studio with LLVM/Clang not found
    exit /b 1
)

:: Set CLANGPP to clang++.exe path
set "CLANGPP=%VS_PATH%\VC\Tools\Llvm\x64\bin\clang++.exe"

if not exist "%CLANGPP%" (
    echo Error: clang++.exe not found at %CLANGPP%
    exit /b 1
)

echo Using clang: %CLANGPP%

:: Run the binding generator
python "%~dp0gen_lua.py" --imgui "%~dp0..\deps\imgui" %*
