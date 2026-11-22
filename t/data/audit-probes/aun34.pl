my @a=(1,2,3); for my $i (0..1) { ($a[$i], $a[$i+1]) = ($a[$i+1], $a[$i]) } print "@a\n";
