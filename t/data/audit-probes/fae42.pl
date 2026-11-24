my $s="abc"; eval { $s=~s/b/X/; die "a\n" }; print "$s\n";
