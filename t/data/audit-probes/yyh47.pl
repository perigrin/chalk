my @a = ((1,2), (3, (4, 5)), ()); my @b = (@a, (), @a[0,1]); my @c = ([1,2], [3]); print scalar(@a), scalar(@b), scalar(@c), "\n";
