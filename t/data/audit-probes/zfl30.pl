my @a=(3,1,2); my @b=(@a, @a=sort { $a <=> $b } @a) if 0; my @c=("@a", scalar(@a=sort { $a <=> $b } @a), "@a"); print join("|", @c), "\n";
