our $x = 1; my $y = 5; *x = \$y; for (1..2) { $x++ } print "$y\n";
