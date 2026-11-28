my $x = 1; my $y = 2; for my $r (\$x, \$y) { $$r *= 3 } print "$x$y\n";
