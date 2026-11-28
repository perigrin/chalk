our $x = 1; my $y = 2; *x = \$y; my $r = \$x; $$r = 9; print "$x$y\n";
