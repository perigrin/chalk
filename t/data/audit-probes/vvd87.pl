my @a = (1,2,3); my @b = @a; my @c = @b = (@b, 4); print "@a|@b|@c\n";
