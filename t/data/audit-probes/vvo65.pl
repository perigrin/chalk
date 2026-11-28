my ($x, $y); sub z { $x = 9; 0 } my @l = (($x = 7), z()); print "@l\n";
