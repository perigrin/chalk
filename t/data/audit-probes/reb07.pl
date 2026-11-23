my $x=0; eval { $x=1; die "a\n" }; $x.=2 if $@; print "$x\n";
