our $g = 1; sub rd { $g } sub f { local $g = 2; my @r = (rd(), rd()); @r } my @l = f(); print "@l", rd(), "\n";
