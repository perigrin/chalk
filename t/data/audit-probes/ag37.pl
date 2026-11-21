my $r = [0]; sub h { $r->[0] = 7 } sub f { h(); "" } print $r->[0], f(), "\n";
