my $s = "abc"; eval { $s =~ s/b/z/; die "x\n" }; print "$s\n";
