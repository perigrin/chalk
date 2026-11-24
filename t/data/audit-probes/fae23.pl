my @a=(1,2,3); my $t=0; eval { for (@a) { $t+=$_; die "x\n" if $_==2 } }; print "$t\n";
