my @a=(1,2); sub d { push @{$_[0]},3; die "a\n" } my $n=@a; eval { d(\@a) }; print $n, scalar(@a), "\n";
