my @c = grep { index("ab", $_) == -1 } ("a", "b", "x"); print "@c\n";
