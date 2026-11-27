my %h = (k=>1); my $c = sub { delete $h{k}; 0 }; my @l = (exists $h{k} ? 1 : 0, $c->(), exists $h{k} ? 1 : 0); print "@l\n";
