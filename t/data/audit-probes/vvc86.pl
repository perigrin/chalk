our $x = 1; my $y = 5; *x = \$y; *x = \42; print "$x$y\n";
