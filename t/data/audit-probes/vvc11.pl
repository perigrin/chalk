our %x = (a=>1); our %y = (b=>2); *x = \%y; $x{c} = 3; print join(",", sort keys %y), "\n";
