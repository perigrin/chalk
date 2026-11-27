my @a=("ab","cd"); my @b = map { (my $t = $_) =~ s/a/X/; $t } @a; print "@a|@b\n";
