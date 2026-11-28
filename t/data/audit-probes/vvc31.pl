our $x = 1; my $y = 7; my $z = 8; *x = \$y; $x++; *x = \$z; $x++; print "$x$y$z\n";
