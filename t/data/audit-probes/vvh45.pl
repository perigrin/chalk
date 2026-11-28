our %g = (a=>1); eval { local %g = (b=>2); die "x\n" }; print join(",", keys %g), "\n";
