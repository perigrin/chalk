my @a = (3,1,2); my @s = sort { $a <=> $b } @a; my @r = reverse @a; my @rs = reverse sort { $a <=> $b } @a; print "@a|@s|@r|@rs|", join("", sort { $a <=> $b } @a[0,1]), "\n";
