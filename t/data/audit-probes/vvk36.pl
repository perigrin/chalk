my @s = sort { $b <=> $a } (3, 1, 2); my @t = reverse sort { $a <=> $b } (3, 1, 2); print "@s|@t\n";
