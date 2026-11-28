my @a = (1); my $r = \@a; sub c { $a[0] = 9; 0 } my @l = ($$r[0], c()); print "@l\n";
