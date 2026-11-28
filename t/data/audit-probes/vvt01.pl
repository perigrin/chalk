my @a = (1,2,3); sub f { $a[0] = 5; $_[0] } my @o; for my $x (@a) { push @o, f($x) } print "@o\n";
