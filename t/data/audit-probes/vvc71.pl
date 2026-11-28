our $x = 1; my $y = 5; for my $i (1..2) { *x = \$y if $i == 2; $x++ } print "$x$y\n";
