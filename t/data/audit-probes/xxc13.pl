my @a=("b","a"); my @s = sort @a; $_ .= "!" for @s; print "@a|@s\n";
