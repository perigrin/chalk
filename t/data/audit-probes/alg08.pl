my @a=(1,2); my @b; eval { for my $x (@a) { $x .= "!"; push @b, $x; die "x\n" if @b == 2 } }; print "@a|@b\n";
