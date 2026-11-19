my %h = (a => 1); my $g = sub { join ",", map { "$_$h{$_}" } sort keys %h }; $h{b} = 2; ($h{c}) = (3); print $g->(), "\n";
