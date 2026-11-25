my @a=(2,1); for (1..2) { print "@a|"; @a=sort { $a <=> $b } @a } print "\n";
