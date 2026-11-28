my @s = sort { length($a) <=> length($b) || $a cmp $b } qw(bb a ccc aa); print "@s\n";
