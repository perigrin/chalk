our $x = 1; sub c { $x = 3; 2 } my $y; print(($y = $x) . c(), "\n");
