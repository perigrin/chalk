our $x = 1; my $y = 2; *x = \$y; $y++; print "$x$y\n";
