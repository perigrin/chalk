our %g = (a=>1,b=>2); { delete local $g{a}; print join(",", sort keys %g) } print join(",", sort keys %g), "\n";
