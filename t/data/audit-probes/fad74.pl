our $g=1; sub f { local $g=2; my $c="NoClass"; $c->new } eval { f() }; print "$g ", $@?1:0, "\n";
