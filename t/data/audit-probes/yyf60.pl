my @a=(1,2,3); for my $x (@a) { if ($x == 2) { $x = 0; last } $x *= 10 } print "@a\n";
