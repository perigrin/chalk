my @a = (1,2,3); sub f { $_[0] .= "x" } for my $x (reverse @a) { f($x) } print "@a\n";
