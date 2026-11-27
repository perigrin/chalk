my $x = 1; my $r = \$x; my $s = ""; for (1..3) { $s .= $x; $$r++ } print "$s\n";
