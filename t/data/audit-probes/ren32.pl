my @a=(1,2); my $e=\$a[0]; my @c=@a; $$e=9; print "@c\n";
