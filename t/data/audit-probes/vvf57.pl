my $x = 1; my $r = \$x; sub c { $$r = 3; 2 } print $x . c(), "\n";
