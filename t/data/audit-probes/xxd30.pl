my $r; { my $x = 1; $r = \$x; } { my $y = 2; print $$r, "\n"; }
