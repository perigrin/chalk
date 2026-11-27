my $x = 1; my $r = \$x; for (1..3) { $$r *= 2; $x++ } print "$x\n";
