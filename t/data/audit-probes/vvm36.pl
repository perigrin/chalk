our @a = (1,2,3); sub f { local @a = @a[1..$#a]; @a ? $a[0] + f() : 0 } print f(), "|@a\n";
