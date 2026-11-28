my $v = 1; my $r = \$v; sub c { $v = 9; 0 } sub id { "@_" } print id($$r, c()), "\n";
