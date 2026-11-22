my $n = 0; eval { for my $x (1,2,3) { $n++; die "m\n" if $x == 2 } }; print "$n\n";
