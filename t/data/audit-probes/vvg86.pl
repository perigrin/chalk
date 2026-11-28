my %h = (a=>1); my $c = sub { $h{a}++ }; my $o = $h{a}; $c->(); print $o, $h{a}, "\n";
