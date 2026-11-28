eval { die "a\n" }; my $e = $@; eval { 1 }; print $e, $@ eq "" ? "clear" : "set", "\n";
