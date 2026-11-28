my $n = 0; eval { for (1..3) { $n++; die "x\n" if $_ == 2 } }; print "$n\n";
