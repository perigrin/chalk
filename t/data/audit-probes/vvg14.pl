my $x = 3; my $r = \$x; my $n = 0; while ($x > 0) { $$r--; $n++ } print "$n\n";
