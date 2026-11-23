my $x=1; eval { $x=2; eval { $x=3; die "i\n" }; $x.=4; die "o\n" }; print "$x $@";
