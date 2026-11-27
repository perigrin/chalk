my @a=([2,"x"],[1,"y"]); my @s = sort { $a->[0] <=> $b->[0] } @a; $s[0][1] = "Z"; print join(",", map { $_->[1] } @a), "\n";
