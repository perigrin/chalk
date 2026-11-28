my @a = (1,2,3); sub f { $_[0] = $_[1] + 1 } for my $i (1..2) { f($a[$i], $a[$i - 1]) } print "@a\n";
