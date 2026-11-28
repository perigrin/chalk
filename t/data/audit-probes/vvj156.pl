my @a = (1,2,3); my @b = \(@a); my @c = (\@a); print scalar(@b), scalar(@c), "\n";
