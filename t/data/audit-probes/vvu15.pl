my @c = grep { index("+-<>", $_) != -1 } split //, "+x<"; print "@c\n";
