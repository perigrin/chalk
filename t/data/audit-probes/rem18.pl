my @a=(1,2); my @b=@a; push @b,3; my @c=@b; $c[0]=7; print "@a|@b|@c\n";
