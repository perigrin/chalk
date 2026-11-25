my @s = sort { substr($a,0,1) cmp substr($b,0,1) } qw(b2 a1 b1 a2 c1 a3 b3 a4 c2 b4 a5 c3); print "@s\n";
