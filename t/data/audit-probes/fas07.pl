my @a=(1,2); { local $"="-"; print "@a"; } print "@a\n";
