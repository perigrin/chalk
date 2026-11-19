my $x = 1; sub d { die "d\n" if $_[0] } eval { $x = 2; d(1); $x = 3; }; print "$x\n";
