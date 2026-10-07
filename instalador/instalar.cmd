@echo off
setlocal EnableExtensions
title YashScript - Instalador / Desinstalador
chcp 65001 >nul 2>nul

set "URL=https://raw.githubusercontent.com/yashioficiala-DEV/YashScript-Roblox-Studio/main/dist/YashScript-Instalador.zip"
set "DEST=%LOCALAPPDATA%\Roblox\Plugins\YashScript"
set "TMP=%TEMP%\yashscript_instalador"

:INICIO
cls
echo.
echo  ================================================
echo     YashScript - Plugin para Roblox Studio
echo  ================================================
echo.

REM --- Detecta o Roblox Studio aberto ---
tasklist /fi "imagename eq RobloxStudioBeta.exe" 2>nul | find /i "RobloxStudioBeta" >nul
if %errorlevel%==0 (
    echo  [AVISO] O Roblox Studio parece estar ABERTO.
    echo  Feche o Studio COMPLETAMENTE e rode de novo.
    echo.
    echo  Pressione qualquer tecla para sair...
    pause >nul
    exit /b 1
)

REM --- Se ja estiver instalado, vira desinstalador / atualizador ---
if exist "%DEST%\plugin.lua" goto JA_INSTALADO

:NOVO
echo  Nenhuma versao encontrada no seu PC.
echo  Vamos instalar a versao mais recente.
echo.
echo  1/3 Baixando do GitHub...
rmdir /s /q "%TMP%" 2>nul
mkdir "%TMP%" 2>nul
curl.exe -L --fail --silent --show-error -o "%TMP%\instalador.zip" "%URL%"
if errorlevel 1 goto ERRO_BAIXAR

echo  2/3 Extraindo...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%TMP%\instalador.zip' -DestinationPath '%TMP%\extraido' -Force" >nul
if errorlevel 1 goto ERRO_EXTRAIR

echo  3/3 Instalando...
if not exist "%LOCALAPPDATA%\Roblox\Plugins" mkdir "%LOCALAPPDATA%\Roblox\Plugins"
if not exist "%DEST%" mkdir "%DEST%"
if exist "%TMP%\extraido\YashScript\plugin.lua" (
    copy /y "%TMP%\extraido\YashScript\plugin.lua" "%DEST%\plugin.lua" >nul
) else (
    copy /y "%TMP%\extraido\*" "%DEST%\" >nul
)
if not exist "%DEST%\plugin.lua" goto ERRO_COPIAR
rmdir /s /q "%TMP%" 2>nul

echo.
echo  ================================================
echo     PRONTO! YashScript foi instalado.
echo  ================================================
echo.
echo   Pasta: %DEST%
echo.
echo   Abra o Roblox Studio e procure o YashScript
echo   na Toolbox (guia Plugins) ou na toolbar.
echo.
echo   Pressione qualquer tecla para sair...
pause >nul
exit /b 0

:JA_INSTALADO
echo  YashScript ja esta instalado neste PC.
echo.
echo  Escolha uma opcao:
echo     [1] Atualizar para a versao mais recente
echo     [2] Desinstalar (remover do PC)
echo     [3] Sair (nao fazer nada)
echo.
set /p "OP=Digite 1, 2 ou 3 e Enter: "
if "%OP%"=="2" goto DESINSTALAR
if "%OP%"=="1" goto ATUALIZAR
exit /b 0

:ATUALIZAR
echo.
echo  Baixando a versao mais recente...
rmdir /s /q "%TMP%" 2>nul
mkdir "%TMP%" 2>nul
curl.exe -L --fail --silent --show-error -o "%TMP%\instalador.zip" "%URL%"
if errorlevel 1 goto ERRO_BAIXAR
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%TMP%\instalador.zip' -DestinationPath '%TMP%\extraido' -Force" >nul
if errorlevel 1 goto ERRO_EXTRAIR
if exist "%TMP%\extraido\YashScript\plugin.lua" (
    copy /y "%TMP%\extraido\YashScript\plugin.lua" "%DEST%\plugin.lua" >nul
) else (
    copy /y "%TMP%\extraido\*" "%DEST%\" >nul
)
if not exist "%DEST%\plugin.lua" goto ERRO_COPIAR
rmdir /s /q "%TMP%" 2>nul
echo.
echo  ATUALIZADO! Feche e reabra o Roblox Studio.
echo  Pressione qualquer tecla para sair...
pause >nul
exit /b 0

:DESINSTALAR
echo.
echo  Tem certeza que quer REMOVER o YashScript?
echo     [S] Sim, desinstalar
echo     [N] Nao, cancelar
echo.
set /p "CONF=Digite S ou N e Enter: "
if /i not "%CONF%"=="S" (
    echo  Cancelado. Nada foi removido.
    echo  Pressione qualquer tecla para sair...
    pause >nul
    exit /b 0
)
rmdir /s /q "%DEST%" 2>nul
if exist "%DEST%" (
    echo  [ERRO] Nao foi possivel remover a pasta.
    echo  Algum arquivo pode estar em uso. Feche o Studio e tente de novo.
    echo  Pressione qualquer tecla para sair...
    pause >nul
    exit /b 1
)
echo.
echo  YashScript foi DESINSTALADO com sucesso.
echo  Pressione qualquer tecla para sair...
pause >nul
exit /b 0

:ERRO_BAIXAR
echo  [ERRO] Nao foi possivel baixar o plugin do GitHub.
echo  Verifique sua conexao com a internet.
pause
exit /b 1

:ERRO_EXTRAIR
echo  [ERRO] Falha ao extrair o arquivo baixado.
pause
exit /b 1

:ERRO_COPIAR
echo  [ERRO] Falha ao copiar o plugin para a pasta do Studio.
pause
exit /b 1