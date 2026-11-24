my $x=0; eval { $x++; eval { $x++; die "i\n" }; $x++; die "o\n"; $x++ }; print "$x\n";
