my $x=1; my $r=\$x; my $v = $x + ($$r = 5) + $x; print "$v\n";
