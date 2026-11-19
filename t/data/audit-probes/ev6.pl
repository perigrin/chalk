my $x = 1; { local $@; eval { $x = 5; die { code => 7 } }; $x += $@->{code} if ref $@ } print "$x\n";
