our $x = 1; sub c { $x = 3; 2 } sub r { my @t = ($x, c()); @t } my @l = r(); print "@l\n";
