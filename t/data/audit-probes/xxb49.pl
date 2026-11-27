my @a=(1,2,3); O: for my $x (@a) { for my $y (@a) { next O if $y == 2; $y = $x + 10 } } print "@a\n";
