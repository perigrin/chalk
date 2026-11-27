my $x=1; my $c = sub { \$x }; ${ $c->() } = 4; print "$x\n";
