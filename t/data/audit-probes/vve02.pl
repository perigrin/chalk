my $x = 1; my $r = \$x; sub f { $$r = 5; $_[0] } print f($x), "\n";
