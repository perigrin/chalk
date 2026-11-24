my $x=1; my $r=\$x; my $y=$x; $$r=2; my $z=$x; undef $r; print "$y$z$x\n";
