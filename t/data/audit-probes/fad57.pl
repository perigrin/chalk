our $g=1; sub f { local $g=2; my $c=$_[0]; $c->() } eval { f(sub { die "cb\n" }) }; print "$g $@";
