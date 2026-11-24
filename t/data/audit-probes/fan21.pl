my @a=(1,2); my $n=0; eval { for my $x (@a) { $n++; $x=0; die "x\n" } }; print "$n @a\n";
