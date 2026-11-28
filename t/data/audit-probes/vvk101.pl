my ($x, $y) = (1, 0); my $n = 0; $x and $n++; $y or $n++; $x && $y || $n++; print "$n\n";
