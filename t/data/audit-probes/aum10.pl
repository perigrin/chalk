our $g=1; eval { my @a = map { die "m\n" } 1; }; print "$g [$@]\n";
