our $x=1; sub f { $x=2; 7 } my @l=($x, f(), $x); print "@l\n";
