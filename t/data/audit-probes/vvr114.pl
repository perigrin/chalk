my @a = (1,2,3); my @i = (0, 1); delete @a[@i]; print defined $a[0] ? "d" : "u", scalar(@a), "\n";
