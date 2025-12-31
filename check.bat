@echo off
setlocal

:: Find lua-language-server from VSCode extensions
set LUA_LS=
for /d %%d in ("%USERPROFILE%\.vscode\extensions\sumneko.lua-*") do (
    if exist "%%d\server\bin\lua-language-server.exe" set LUA_LS=%%d\server\bin\lua-language-server.exe
)

if "%LUA_LS%"=="" (
    echo lua-language-server not found
    echo Install sumneko.lua extension in VSCode
    exit /b 1
)

echo Checking mane3d...
"%LUA_LS%" --check "%~dp0."

echo.
echo Done.
