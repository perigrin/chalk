my @a=(1,2,3); { local $" = ":"; print "@a\n"; } sub s1 { "@_" } { local $" = ","; print s1(@a), "\n"; } print "@a\n";
