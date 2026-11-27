our @a=(1); sub f { $a[0]=5; $_[0] } for my $x (@a) { print f($x) } print "\n";
