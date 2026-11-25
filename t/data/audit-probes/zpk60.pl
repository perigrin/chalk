our $x=1; my $c=sub { $x }; my $o=$c->(); $x=2; print $o, $c->(), "\n";
