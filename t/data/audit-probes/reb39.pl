our $g=1; my $r=sub { local $g=9; die "c\n" }; eval { $r->() }; print "$g $@";
