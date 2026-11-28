my @a = ("ab", "cd"); my @b = map { (my $t = $_) =~ s/[ac]/z/; $t } @a; print "@a|@b\n";
