sub f { my $c = sub { $_[0] = "c" }; $c->(@_) } my $x="o"; f($x); print "$x\n";
