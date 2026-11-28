our $x = 1; sub c { local $x = 3; 2 } my @l = ($x, c(), $x); print "@l\n";
