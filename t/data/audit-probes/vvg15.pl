my $x = 3; my $r = \$x; my $n = 0; while ($$r > 0) { $x--; $n++ } print "$n\n";
