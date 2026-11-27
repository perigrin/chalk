my @a = (1,2,3); my ($f,@rest) = \(@a); ${$rest[1]} = 9; print "@a\n";
