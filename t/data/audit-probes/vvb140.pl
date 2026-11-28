my @a = (1,2,3); sub f { $_[0] *= 2 } for my $i (0..$#a) { f($a[$i]) } print "@a\n";
