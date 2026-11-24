my $x=1; my $r=\$x; my $v = $x . ($$r = "z"); print "$v\n";
