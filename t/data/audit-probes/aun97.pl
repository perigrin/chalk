our $g=1; eval { local $g = 2; my @a = (1,2); my $s = join(",", map { $_ == 2 ? die("j\n") : $_ } @a); }; print "$g $@";
