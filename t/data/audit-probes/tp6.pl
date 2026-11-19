our $total = 0; sub add { $total += $_[0] } for my $x (1..4) { add($x); $total = $total * 1 } print "$total\n";
