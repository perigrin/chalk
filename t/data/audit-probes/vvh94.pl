my $n = 0; eval { while (1) { $n++; die "x\n" if $n == 3 } }; print "$n\n";
