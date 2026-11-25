my @a=(1,2); { local $"="-"; print "@a\n"; } print "@a\n";
