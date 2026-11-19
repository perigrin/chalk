sub f { $_[1] = 3 } my @a = (1); my $y = 2; f(@a, $y); print "@a $y\n";
