my $n = 0; sub d { $n++; die "x\n" if $_[0]; $n++ } eval { d(0); d(1); d(0) }; print "$n $@";
