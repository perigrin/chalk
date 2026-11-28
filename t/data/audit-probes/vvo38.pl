my ($x, $y); sub z { $x = 9; 0 } my @l = ((($x, $y) = (7,8)), z(), $x); print "@l\n";
