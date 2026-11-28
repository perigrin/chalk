our $x = 1; sub c { $x = 3; 2 } print((my $y = $x) . c(), "\n");
