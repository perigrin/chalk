our $g=1; sub f { my $z=shift; local $g=2; my @l=(1,2); my $q=$l[0]/$z; } eval { f(0) }; eval { f(1) }; print "$g\n";
