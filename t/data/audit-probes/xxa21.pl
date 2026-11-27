sub f { $_[0] = 5; 1 } our $x=1; my @l = ($x, f($x), $x); print "@l\n";
