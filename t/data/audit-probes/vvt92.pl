sub f { $_[0]++; 0 } my @t; my @a = (1,2,3); for my $x (@a) { push @t, $x . f($x) . $x } print "@t\n";
