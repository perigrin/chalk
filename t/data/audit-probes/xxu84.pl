our $x = "ab"; sub c { $x = "cd"; 1 } my @l = (uc $x, c(), length $x); print "@l\n";
