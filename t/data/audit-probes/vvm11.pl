our %h = (a=>1); eval { local %h = (b=>2); die "x\n" }; print join(",", keys %h), "\n";
