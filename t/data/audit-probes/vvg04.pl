my $x = 1; my $y = 2; my $r = \$x; $r = \$y; $$r = 5; print "$x$y\n";
