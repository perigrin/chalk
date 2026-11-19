my $e; { local $@; eval { die { code => 7 } }; $e = $@ } print ref($e), "\n";
