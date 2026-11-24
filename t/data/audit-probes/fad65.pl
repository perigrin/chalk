our $g=1; sub f { local $g=2; my $x = $_[0] ? die("y\n") : 5; $x } print f(0), $g; eval { f(1) }; print "$g\n";
