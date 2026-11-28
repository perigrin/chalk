my $x = 1; my @a = (0); splice(@a, 0, 0, $x, $x++); print "@a\n";
