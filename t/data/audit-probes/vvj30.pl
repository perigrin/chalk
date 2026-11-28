my @a = (1,2,3); my @b = (@a, 4)[1..3]; my @c = (reverse @a)[0]; print "@b|@c\n";
