my $x=1; my $r=\$x; $x = 2; my $v = $$r; $x = 3; print "$v$$r\n";
