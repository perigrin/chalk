my @a = (1); my $r = \@a; sub c { $a[0] = 9; 0 } my $s = "@$r" . c(); print "$s\n";
