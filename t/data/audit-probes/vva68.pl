our $x = 1; sub f { local $x = 2; return $x } my @l = (f(), $x); print "@l\n";
