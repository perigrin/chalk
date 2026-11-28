my @c = grep { index("ab", $_) >= 0 } ("a", "b", "x"); print "@c\n";
