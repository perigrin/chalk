our $g=1; eval { local $g=2; my @s=sort { die "c\n" } 2,1; }; print "$g $@";
