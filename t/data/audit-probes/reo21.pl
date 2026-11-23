my @a=(1,2); my @b = map { my $v=$_; $_=0; $v } @a; print "@a|@b\n";
