our @a = (1,2,3); sub s2 { local $a[1] = $_[0]; "@a" } print s2(7), s2(8), "@a\n";
