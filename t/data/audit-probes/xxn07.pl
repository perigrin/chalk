our $x = 1; our $y = 2; for my $i (1) { *x = \$y } $x++; print "$x$y\n";
