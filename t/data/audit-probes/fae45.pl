my $x=1; my $y = (eval { $x=2; die "a\n"; 1 } ? 0 : $x) + $x; print "$y\n";
