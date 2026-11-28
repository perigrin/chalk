my @a = (1,2,3); sub f { $_[0]++; $_[1]++ } for my $x (@a) { f($x, $x) } print "@a\n";
