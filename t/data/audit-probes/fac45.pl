my @a=(1,2); my @b=@a; my @c=@b; @b=(); $c[0]=5; print "@a|@c\n";
