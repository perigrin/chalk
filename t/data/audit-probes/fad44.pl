my %h; sub d { die "x\n" } eval { $h{x}=d() }; print exists $h{x} ? 1 : 0, "\n";
