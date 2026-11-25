my @a=(1,2); my $r=\$a[0]; my @b=@a; $$r=9; print "@b|@a\n";
