our $x = 1; sub c { $x = 3; 2 } sub r { return ($x, c()) } my @l = r(); print "@l\n";
