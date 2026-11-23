our $g=1; sub f { local $g=2; my $z=shift; my $v = 1/$z; $v } my $v = eval { f(0) }; print "$g\n";
