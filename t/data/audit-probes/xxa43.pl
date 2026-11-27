sub f { my $c = sub { $_[0] = "c" }; $c->($_[0]) } my $x="o"; f($x); print "$x\n";
