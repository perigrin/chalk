my @s = sort { lc($a) cmp lc($b) } qw(b A c); my @n = sort { $a <=> $b } qw(10 9 2); print "@s@n\n";
