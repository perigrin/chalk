my %h = (a=>1); sub d { die "x\n" } eval { $h{b} = d() }; print join(",", sort keys %h), "\n";
