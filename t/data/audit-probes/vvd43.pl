my ($x, $y) = (10, 4); ($x, $y) = ($y, $x % $y) while $y; print "$x\n";
