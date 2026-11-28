our $x = 1; my $y = 5; *x = \$y; my @l = ($x, $y++, $x); print "@l\n";
