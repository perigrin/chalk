my @a = (1,2,3); my $r = [@a, [@a]]; $a[0] = 9; print $r->[0], $r->[3][0], scalar(@$r), "\n";
