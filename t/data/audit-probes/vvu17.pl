my @c = grep { rindex("abca", $_) > -1 } ("a", "c", "x"); print "@c\n";
