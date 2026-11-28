my $x = 3; my $r = \$x; my $n = 0; for (1..3) { $n += $x; $$r++ } print "$n\n";
