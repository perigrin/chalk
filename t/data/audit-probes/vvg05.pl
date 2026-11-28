my $x = 1; my $y = 2; my $r = 0 ? \$x : \$y; $$r = 5; print "$x$y\n";
