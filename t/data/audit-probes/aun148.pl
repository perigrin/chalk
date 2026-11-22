sub app { push @{$_[0]}, 3 } my @a = (1,2); my $n = @a; app(\@a); print "$n ", scalar(@a), " @a\n";
