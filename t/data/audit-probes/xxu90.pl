our $x = 1; sub c { $x = 3; 2 } my @l = ($x, $x + 0, "$x", c(), $x); print "@l\n";
