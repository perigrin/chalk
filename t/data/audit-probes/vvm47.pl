our @a = (1,2,3); our @b = (4); { local (@a, @b) = (7, 8); print scalar(@a), scalar(@b) } print "@a|@b\n";
