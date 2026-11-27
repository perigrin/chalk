my @w=qw(bb a ccc); my @s = sort { length($a) <=> length($b) } @w; print "@s\n";
