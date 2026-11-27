my $x=1; my $r=\$x; my @l = ($x, $$r++, $x, ++$$r, $x); print "@l\n";
