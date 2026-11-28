my $x = 1; my $r = \$x; print $x . ($$r = 3), "\n";
