my @s = sort { lc($a) cmp lc($b) or $a cmp $b } qw(b A a B c); my @t = sort { length($a) <=> length($b) || $a cmp $b } qw(ccc a bb aa b); print "@s|@t\n";
