my $x=1; my $r=\$x; my $t=0; for (1..3) { $x++; $t+=$$r } print "$t\n";
