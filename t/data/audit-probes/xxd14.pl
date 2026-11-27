my ($x,$y)=(1,2); my $r = \$x; $r = \$y if $x; $$r = 9; print "$x $y\n";
