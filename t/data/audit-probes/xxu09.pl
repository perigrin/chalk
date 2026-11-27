our $x = 1; sub c { $x = 3; 2 } my @a; push @a, $x, c(); print "@a\n";
