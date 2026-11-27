my ($x,$y)=(1,2); my $r = 1 ? \$x : \$y; $$r = 9; my $q = $x > 5 ? \$y : \$x; $$q = 8; print "$x $y\n";
