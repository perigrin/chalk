my %o = (a => 2, b => 1); my @s = sort { $o{$a} <=> $o{$b} } keys %o; print "@s\n";
