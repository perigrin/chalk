sub t { eval { die "x\n" }; $@ } my $e=t(); eval { 1 }; print $e;
