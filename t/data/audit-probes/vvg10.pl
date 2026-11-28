my $x = 1; my $r = \$x; my $v = $x; $$r = 2; $v .= $x; print "$v\n";
