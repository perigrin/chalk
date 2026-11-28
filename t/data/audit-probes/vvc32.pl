our $x = 1; my @a = (1,2,3); for my $i (0..2) { *x = \$a[$i]; $x *= 2 } print "@a\n";
