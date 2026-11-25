my @a=(1,2); my @c=@a; my $r=\$a[0]; $$r=9; print "@c|@a\n";
