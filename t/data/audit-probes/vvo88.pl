sub two { my ($x, $y); ((($x, $y) = (7,8)), $x = 9) } my @l = two(); print "@l\n";
