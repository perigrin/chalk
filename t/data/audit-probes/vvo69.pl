my ($x, $y) = (1); my @l = (($x ||= 7), $x = 9); print "@l\n";
