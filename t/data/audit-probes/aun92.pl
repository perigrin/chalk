our $g=1; eval { local $g = 2; my @a = (1); my $i = 5; my $x = substr("abc", $i, 1); my %h = map { die "m\n" } @a; }; print "$g $@";
