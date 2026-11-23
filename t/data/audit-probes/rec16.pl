our $g=1; { local $g=2; my $z=0; eval { 1/$z }; } print "$g\n";
