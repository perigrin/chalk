our $x=1; my $c = sub { $x }; sub f { local $x=2; print $c->() } f(); print $c->(), "\n";
