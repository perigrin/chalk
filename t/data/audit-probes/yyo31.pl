use sort 'stable'; my @s = sort { substr($a,0,1) cmp substr($b,0,1) } qw(b2 a1 b1 a2); print "@s\n";
