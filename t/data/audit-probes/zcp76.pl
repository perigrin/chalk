my @a=("a\n"); my @c=@a; chomp @a; print length($c[0]), length($a[0]), "\n";
