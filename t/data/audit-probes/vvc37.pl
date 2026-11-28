our $x = 1; my $y = 2; if (!$y) { *x = \$y } $x = 5; print "$x$y\n";
