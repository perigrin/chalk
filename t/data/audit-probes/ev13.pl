my %h; eval { $h{a} = 1; die "x\n"; $h{b} = 2 }; print join(",", sort keys %h), "\n";
