my ($p, $q) = (1, 2); sub f { $_[0] .= "x" } for my $x ($p, $q) { f($x) } print "$p$q\n";
