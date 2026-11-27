my $h = {k=>1}; my $keep = $h; my $c = sub { $h = {k=>9}; 0 }; my @l = ($h->{k}, $c->(), $h->{k}); print "@l\n";
