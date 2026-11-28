my $x = 1; my $r = \$x; my $s = "$x"; $$r = 2; print "$s$x\n";
