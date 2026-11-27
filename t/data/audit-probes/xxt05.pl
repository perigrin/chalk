my $x = 1; my $c = sub { $x++; () }; my %h = (a => $x, $c->(), b => $x); print "$h{a}$h{b}\n";
