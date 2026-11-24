my $x=1; my $y = eval { $x=2; die "a\n" } // $x; print "$y\n";
