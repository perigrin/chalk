my @a=(1,2,3); sub t { for my $x (@a) { if ($x == 2) { $x = 0; return "r" } $x *= 10 } "e" } print t(), "@a\n";
