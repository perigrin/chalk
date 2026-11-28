our $x = 1; my $y = 5; *x = \42; *x = \$y; $x++; print "$x$y\n";
