my @a=(3,1,2); for my $x (sort { $a <=> $b } @a) { $x *= 10 } print "@a\n";
