my @a = (1,2,3); my @b; my ($x,$y) = @b[1,0] = @a[1,2]; print "$x$y|", join(",", map { $_ // "u" } @b), "\n";
