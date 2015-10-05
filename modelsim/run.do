make -f Makefile
vsim -t 1ns work.opa_sim_tb -voptargs="+acc"
set StdArithNoWarnings 1
set NumericStdNoWarnings 1
do wave.do
radix -hexadecimal
run 64us
wave zoomfull
radix -hexadecimal
