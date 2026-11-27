our $g = 1; sub rd { $g } sub f { local $g = 2; return (rd(), $g) } my @l = f(); print "@l", rd(), "\n";
