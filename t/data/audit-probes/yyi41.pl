sub mod { my ($a1, $h1) = @_; $a1->[0] = "A"; $h1->{k} = "H"; @$a1 = (@$a1, "more") } my @a=(1); my %h; mod(\@a, \%h); print "@a $h{k}\n";
