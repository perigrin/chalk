my @a = (1,2,3); sub f { $_[0] *= 2; $a[0] } my @o; for my $x (@a) { push @o, f($x) } print "@o|@a\n";
