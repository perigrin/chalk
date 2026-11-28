my %h = (a=>1); my $c = sub { $h{b} = 2 }; my $o = keys %h; $c->(); print $o, scalar(keys %h), "\n";
