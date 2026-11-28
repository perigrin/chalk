my $v = 1; my $r = \$v; sub c { $v = 9; 0 } print $$r, c(), "\n";
