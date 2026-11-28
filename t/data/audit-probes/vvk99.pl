my ($x, $y) = (0, 2); my $v = $x || $y; my $w = $x && $y; my $u = $x // $y; print "$v$w$u\n";
