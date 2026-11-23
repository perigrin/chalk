my @a=(1,2); my $r=\@a; my @c=@$r; $c[0]=9; print "@a\n";
