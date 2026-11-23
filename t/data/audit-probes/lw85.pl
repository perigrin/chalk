my @a=(1,2); for my $x (@a) { my $r = \$x; $$r .= "x"; last if $$r eq "1x" } print "@a\n";
