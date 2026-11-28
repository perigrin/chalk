my @a = (1,2,3); my $s = 0; $s += $_ for @a; my $p = 1; $p *= $_ foreach @a; print "$s$p\n";
