sub f { my @r = eval { (1,2) }; scalar @r } print f(),"\n";
