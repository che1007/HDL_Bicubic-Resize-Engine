# operating conditions and boundary conditions #

set cycle 52.2  
create_clock -name CLK  -period $cycle   [get_ports  CLK] 


#Don't touch the basic env setting as below
set_input_delay  5.0   -clock CLK [remove_from_collection [all_inputs] [get_ports CLK]]
set_output_delay 5.0    -clock CLK [all_outputs] 
