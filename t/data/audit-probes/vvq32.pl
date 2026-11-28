my @a = (1); my $r = \@a; sub c { $a[0] = 9; 0 } my $s = $r->[0] . c(); print "$s\n";
