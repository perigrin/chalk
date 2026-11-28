my @a = (1,2,3); sub f { $_++ for @a; $_[0] } my @o; for my $x (@a) { push @o, f($x) } print "@o\n";
