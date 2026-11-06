@echo off
rem Doom Runner - Starter / launcher
rem  - DOOM2.WAD in this folder  -> original Doom II graphics and sounds (recommended!)
rem  - otherwise                 -> Freedoom (free replacement, included)
rem  - brutal*.pk3 in this folder -> Brutal Doom is loaded too (recommended!)
cd /d "%~dp0"
set "IWAD=freedoom2.wad"
if exist "DOOM2.WAD" set "IWAD=DOOM2.WAD"
set "BD="
for %%f in (brutal*.pk3) do set "BD=%%f"
if defined BD (
  start "" "%~dp0gzdoom.exe" -iwad "%IWAD%" -file "%BD%" "DoomRunner.pk3" -config "%~dp0DoomRunner.ini"
) else (
  start "" "%~dp0gzdoom.exe" -iwad "%IWAD%" -file "DoomRunner.pk3" -config "%~dp0DoomRunner.ini"
)
