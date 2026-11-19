my $x = 1; my $r = \$x; my $v = ($$r = 5) + $x; print "$v\n";
