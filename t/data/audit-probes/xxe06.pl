our $x = 1; my $r = \$x; our $y = 2; *x = \$y; $$r = 9; print "$x $y\n";
