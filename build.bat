echo off
"../rgbgfx" -o tiles.2bpp tiles.png
echo on
"../rgbasm" -o test.o test.asm
echo off
"../rgblink" -o test.gb test.o
"../rgbfix" -v -p 0 test.gb
echo on