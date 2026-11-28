our $x = 1; my @a = (1,2,3); for my $e (@a) { *x = \$e; $x *= 2 } print "@a\n";
