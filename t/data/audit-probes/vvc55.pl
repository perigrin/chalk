our $x = 1; my $y = 2; my $g = *x; *$g = \$y; print "$x\n";
