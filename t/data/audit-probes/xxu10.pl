our $x = 1; sub c { $x = 3; 2 } my @a = (0); unshift @a, $x, c(); print "@a\n";
