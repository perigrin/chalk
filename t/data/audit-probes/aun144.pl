my $x = 1; my $r = \$x; my $g = sub { $$r = 7 }; my $a = $x; $g->(); print "$a $x\n";
