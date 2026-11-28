our $x = 1; my $y = "ab"; *x = \$y; chop $x; print "$y\n";
