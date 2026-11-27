our $x = 1; sub c { $x = 3; 2 } my @l = map { $_ * 10 } $x, c(); print "@l\n";
