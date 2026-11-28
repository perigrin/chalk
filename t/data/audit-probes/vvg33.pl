my @a = (1,2,3); my $r = \@a; my @b = @$r; $b[0] = 9; print "@a\n";
