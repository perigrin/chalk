sub f { my $c = sub { 1 }; $c->() }
sub g { my $c = sub { 2 }; $c->() }
my $t = sub { 42 };
print $t->();
