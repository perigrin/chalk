my @a = (1,2,3); $#a = 0; my @b = (1); $#b = 2; my @c = (1,2); $#c = -1; $c[2] = 5; print scalar(@a), scalar(@b), defined $b[2] ? "d" : "u", scalar(@c), defined $c[0] ? "d" : "u", "\n";
