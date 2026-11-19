my $x = 1; print "$x\n"; my $r = \$x; $$r = 3; print "$x\n";
