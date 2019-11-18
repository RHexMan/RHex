@echo off
TITLE RHexCloseAll
REM Running RHexCloseAll

taskkill /F /IM perl.exe /IM gnuplot.exe /T

exit 0
