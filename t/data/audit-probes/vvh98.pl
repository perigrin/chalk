my $s = "abc"; eval { $s =~ s/b/die "x\n"/e }; print "$s\n";
