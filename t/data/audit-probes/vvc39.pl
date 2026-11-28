our $x = 1; my $y = 2; my $r = \$x; *x = \$y; $$r = 9; print "$x$y$$r\n";
