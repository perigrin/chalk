my @a = (1,2,3); sub f { $_[0] .= "x" } for my $x (@a[0,1]) { f($x) } print "@a\n";
