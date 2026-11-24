our $g=1; sub f { my $c=shift; if ($c) { local $g=2; } my $z=0; return 1/$c } eval { f(0) }; print "$g\n";
