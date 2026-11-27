my ($x,$y)=(1,2); for my $r (\$x, \$y) { $$r += $x } print "$x $y\n";
