my $n = 0; for (1..3) { eval { $n++; die "x\n" }; $n += 10 if $@ } print "$n\n";
