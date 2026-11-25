our @a=(1); for (1..2) { print "@a|"; local @a=(5); } print "@a\n";
