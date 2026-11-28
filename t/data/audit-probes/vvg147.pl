my $x = 1; my $r = \$x; my $w = $r; undef $r; $$w = 4; print "$x\n";
