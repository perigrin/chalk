my @a = (1,2,3); my @b = (4); sub f { $_[0] .= "x" } for my $x (@a, @b) { f($x) } print "@a|@b\n";
