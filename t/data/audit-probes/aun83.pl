our $g = 1; eval { local $g = 2; open(my $fh, "<", "/nonexistent/x") or die "no\n"; }; print "$g $@";
