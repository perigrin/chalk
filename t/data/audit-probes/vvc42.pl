our $x = 1; my $y = 2; { local *x; *x = \$y; $x = 5 } print "$x$y\n";
