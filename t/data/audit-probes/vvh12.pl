my %h; eval { $h{a} = 1; die "z\n" }; print join(",", keys %h), "\n";
